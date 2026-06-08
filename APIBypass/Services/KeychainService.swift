import Foundation
import Security

actor KeychainService {
    static let shared = KeychainService()

    private let service: String
    private let storageKey = "all-api-keys"
    private var cache: [String: String] = [:]

    internal init(service: String = "com.apibypass.apikey") {
        self.service = service
    }

    func save(_ value: String, forKey key: String) throws {
        // 更新缓存
        cache[key] = value

        // 保存到合并存储
        try saveToKeychain()
    }

    func retrieve(forKey key: String) throws -> String {
        // 优先从缓存获取
        if let cached = cache[key] {
            return cached
        }

        // 从 Keychain 加载所有 keys
        try loadFromKeychain()

        guard let value = cache[key] else {
            throw KeychainError.keyNotFound
        }
        return value
    }

    func delete(forKey key: String) throws {
        cache.removeValue(forKey: key)

        if cache.isEmpty {
            // 清空则删除整个 Keychain item
            deleteFromKeychain()
        } else {
            try saveToKeychain()
        }
    }

    /// 预加载所有 API Keys 到缓存
    func preloadKeys(for mappingIds: [String]) {
        do {
            try loadFromKeychain()
        } catch {
            // 首次使用或加载失败，忽略
        }

        // 迁移旧格式数据
        migrateOldKeys(mappingIds: mappingIds)
    }

    /// 迁移旧格式（每个 key 单独存储）到新格式（合并存储）
    private func migrateOldKeys(mappingIds: [String]) {
        var migrated = false

        for key in mappingIds {
            // 如果缓存中已有，跳过
            if cache[key] != nil { continue }

            // 尝试读取旧格式
            let oldQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(oldQuery as CFDictionary, &result)

            if status == errSecSuccess,
               let data = result as? Data,
               let value = String(data: data, encoding: .utf8) {
                cache[key] = value
                migrated = true

                // 删除旧 item
                let deleteQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: key
                ]
                SecItemDelete(deleteQuery as CFDictionary)
            }
        }

        // 如果有迁移，保存到新格式
        if migrated {
            try? saveToKeychain()
        }
    }

    // MARK: - Private Methods

    private func loadFromKeychain() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: storageKey,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            // 无数据或解析失败，保持缓存为空
            return
        }

        cache = json
    }

    private func saveToKeychain() throws {
        let jsonData = try JSONSerialization.data(withJSONObject: cache)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: storageKey,
            kSecValueData as String: jsonData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        // 尝试添加
        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // 已存在，更新
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: storageKey
            ]
            let updateStatus = SecItemUpdate(
                updateQuery as CFDictionary,
                [kSecValueData as String: jsonData] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.saveFailed(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.saveFailed(status)
        }
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: storageKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error {
    case keyNotFound
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
}
