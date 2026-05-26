# 提供商配置功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将"提供商配置"（baseURL + API Key + 提供商类型）从"模型映射"中分离，实现按提供商分类管理，避免重复配置。

**Architecture:** 新增 ProviderConfig 数据模型，ConfigManager 扩展管理 providers 列表。UI 侧将主窗口左侧列表分为"提供商"和"模型映射"两个分组，映射详情用下拉选择关联提供商。新增数据迁移逻辑，将旧映射自动按 (apiProvider, baseURL) 分组为 ProviderConfig。

**Tech Stack:** SwiftUI, Swift 6, Hummingbird, Keychain

---

## 文件结构

| 操作 | 文件 | 职责 |
|------|------|------|
| 新增 | `APIBypass/Models/ProviderConfig.swift` | ProviderConfig 数据模型 |
| 修改 | `APIBypass/Models/ModelMapping.swift` | 移除 apiProvider/baseURL，新增 providerConfigId |
| 修改 | `APIBypass/Core/ConfigManager.swift` | 新增 providers CRUD、迁移逻辑 |
| 修改 | `APIBypass/Core/HTTPServer.swift` | 通过 mapping.providerConfigId 查找 provider 获取 apiKey/baseURL/apiProvider |
| 修改 | `APIBypass/UI/ConfigWindow.swift` | 左侧列表分组、选中状态管理、删除逻辑 |
| 修改 | `APIBypass/UI/Views/MappingListView.swift` | 更新列表显示，使用 providerConfigId 查找提供商名称 |
| 修改 | `APIBypass/UI/Views/MappingDetailView.swift` | 替换 apiProvider/baseURL/apiKey 为提供商下拉选择 |
| 新增 | `APIBypass/UI/Views/ProviderDetailView.swift` | 提供商详情编辑视图 |
| 新增 | `APIBypass/UI/Views/NewProviderView.swift` | 新建提供商 Sheet |
| 修改 | `APIBypass/Core/LocalizationManager.swift` | 新增 i18n key |
| 修改 | `APIBypass/APIBypassApp.swift` | keychain 预加载改为 provider ids |

---

### Task 1: 新增 ProviderConfig 数据模型

**Files:**
- Create: `APIBypass/Models/ProviderConfig.swift`

- [ ] **Step 1: 创建 ProviderConfig.swift**

```swift
import Foundation

struct ProviderConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var apiProvider: APIProvider
    var baseURL: URL

    init(
        id: UUID = UUID(),
        name: String,
        apiProvider: APIProvider,
        baseURL: URL
    ) {
        self.id = id
        self.name = name
        self.apiProvider = apiProvider
        self.baseURL = baseURL
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `swift build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED（新文件还未被引用，不影响编译）

- [ ] **Step 3: Commit**

```bash
git add APIBypass/Models/ProviderConfig.swift
git commit -m "feat: add ProviderConfig data model"
```

---

### Task 2: 修改 ModelMapping 数据模型

**Files:**
- Modify: `APIBypass/Models/ModelMapping.swift`

- [ ] **Step 1: 修改 ModelMapping 结构体**

移除 `apiProvider` 和 `baseURL` 字段，新增 `providerConfigId` 字段。修改 init 和 matches 方法。

```swift
struct ModelMapping: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var incomingModel: String
    var actualModel: String
    var providerConfigId: UUID
    var parameters: InjectedParameters
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        incomingModel: String,
        actualModel: String,
        providerConfigId: UUID,
        parameters: InjectedParameters,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.incomingModel = incomingModel
        self.actualModel = actualModel
        self.providerConfigId = providerConfigId
        self.parameters = parameters
        self.isEnabled = isEnabled
    }

    func matches(model: String) -> Bool {
        isEnabled && incomingModel == model
    }
}
```

注意：此步会引入编译错误（其他文件仍引用 mapping.apiProvider/baseURL），将在后续 Task 中修复。

- [ ] **Step 2: Commit**

```bash
git add APIBypass/Models/ModelMapping.swift
git commit -m "feat: update ModelMapping to use providerConfigId"
```

---

### Task 3: 扩展 ConfigManager

**Files:**
- Modify: `APIBypass/Core/ConfigManager.swift`

- [ ] **Step 1: 添加 providers 管理和迁移逻辑**

```swift
import Foundation
import Combine

final class ConfigManager: ObservableObject {
    @Published var mappings: [ModelMapping] = []
    @Published var providers: [ProviderConfig] = []

    private let defaultsKey: String
    private let providersDefaultsKey = "com.apibypass.providers"
    private let migrationKey = "com.apibypass.migratedToProviders"
    private let defaults = UserDefaults.standard

    init(defaultsKey: String = "com.apibypass.mappings") {
        self.defaultsKey = defaultsKey
        load()
    }

    // MARK: - Provider CRUD

    func addProvider(_ provider: ProviderConfig) {
        providers.append(provider)
        saveProviders()
    }

    func updateProvider(_ provider: ProviderConfig) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
            saveProviders()
        }
    }

    func deleteProvider(_ id: UUID) {
        providers.removeAll { $0.id == id }
        saveProviders()
    }

    func findProvider(for id: UUID) -> ProviderConfig? {
        providers.first { $0.id == id }
    }

    func mappingsForProvider(_ providerId: UUID) -> [ModelMapping] {
        mappings.filter { $0.providerConfigId == providerId }
    }

    func isProviderValid(for mapping: ModelMapping) -> Bool {
        providers.contains { $0.id == mapping.providerConfigId }
    }

    // MARK: - Mapping CRUD

    func add(_ mapping: ModelMapping) {
        mappings.append(mapping)
        save()
    }

    func update(_ mapping: ModelMapping) {
        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = mapping
            save()
        }
    }

    func delete(_ id: UUID) {
        mappings.removeAll { $0.id == id }
        save()
    }

    func findMapping(for model: String) -> ModelMapping? {
        mappings.first { $0.matches(model: model) }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func saveProviders() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        defaults.set(data, forKey: providersDefaultsKey)
    }

    private func load() {
        // 加载 providers
        if let data = defaults.data(forKey: providersDefaultsKey),
           let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            providers = decoded
        }

        // 加载 mappings
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([ModelMapping].self, from: data) {
            mappings = decoded
        }

        // 迁移旧数据
        migrateIfNeeded()
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        guard !defaults.bool(forKey: migrationKey) else { return }
        guard !mappings.isEmpty else {
            defaults.set(true, forKey: migrationKey)
            return
        }

        // 检测旧格式：如果 mapping 有 apiProvider 字段但缺少 providerConfigId，
        // 说明是旧数据。但因为我们已改了 ModelMapping 结构，
        // 旧数据的解码会失败（apiProvider 字段无法映射）。
        // 所以我们需要用原始 JSON 解析来迁移。

        guard let data = defaults.data(forKey: defaultsKey),
              let oldMappings = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            defaults.set(true, forKey: migrationKey)
            return
        }

        // 按 (apiProvider, baseURL) 分组
        var groups: [String: (provider: ProviderConfig, mappingIndices: [Int])] = [:]
        var groupOrder: [String] = []

        for (index, oldMapping) in oldMappings.enumerated() {
            guard let apiProviderRaw = oldMapping["apiProvider"] as? String,
                  let apiProvider = APIProvider(rawValue: apiProviderRaw),
                  let baseURLString = oldMapping["baseURL"] as? String,
                  let baseURL = URL(string: baseURLString) else { continue }

            let groupKey = "\(apiProviderRaw)|\(baseURLString)"

            if groups[groupKey] == nil {
                let baseName = apiProvider == .openai ? "OpenAI" : "Anthropic"
                var name = baseName
                var counter = 2
                while providers.contains(where: { $0.name == name }) {
                    name = "\(baseName) \(counter)"
                    counter += 1
                }
                let provider = ProviderConfig(name: name, apiProvider: apiProvider, baseURL: baseURL)
                groups[groupKey] = (provider: provider, mappingIndices: [])
                groupOrder.append(groupKey)
            }
            groups[groupKey]?.mappingIndices.append(index)
        }

        // 创建 ProviderConfig 和更新 Mapping
        var providerIdMap: [String: UUID] = [:]

        for groupKey in groupOrder {
            guard let group = groups[groupKey] else { continue }
            let provider = group.provider
            providers.append(provider)
            providerIdMap[groupKey] = provider.id
        }

        // 重建 mappings，替换 apiProvider/baseURL 为 providerConfigId
        var newMappings: [ModelMapping] = []
        for (index, oldMapping) in oldMappings.enumerated() {
            guard let apiProviderRaw = oldMapping["apiProvider"] as? String,
                  let baseURLString = oldMapping["baseURL"] as? String else { continue }

            let groupKey = "\(apiProviderRaw)|\(baseURLString)"
            guard let providerId = providerIdMap[groupKey] else { continue }

            // 从旧数据重建 mapping
            var mappingDict = oldMapping
            mappingDict.removeValue(forKey: "apiProvider")
            mappingDict.removeValue(forKey: "baseURL")
            mappingDict["providerConfigId"] = providerId.uuidString

            if let mappingData = try? JSONSerialization.data(withJSONObject: mappingDict),
               let mapping = try? JSONDecoder().decode(ModelMapping.self, from: mappingData) {
                newMappings.append(mapping)
            }
        }

        mappings = newMappings
        save()
        saveProviders()

        // 迁移 API Key：从 mapping.id key 复制到 provider.id key
        let keychain = KeychainService.shared
        for groupKey in groupOrder {
            guard let group = groups[groupKey],
                  let providerId = providerIdMap[groupKey] else { continue }

            // 从第一个映射获取 API Key
            if let firstIndex = group.mappingIndices.first,
               firstIndex < oldMappings.count,
               let oldId = oldMappings[firstIndex]["id"] as? String {
                if let apiKey = try? keychain.retrieve(forKey: oldId) {
                    try? keychain.save(apiKey, forKey: providerId.uuidString)
                }
            }
        }

        defaults.set(true, forKey: migrationKey)
        print("[Migration] Migrated \(providers.count) providers and \(mappings.count) mappings")
    }
}
```

注意：此实现中 `migrateIfNeeded` 使用 `JSONSerialization` 原始解析旧数据，因为 `ModelMapping` 结构已变更，无法直接 decode 旧格式。这种方法不需要保留旧字段的兼容性。

- [ ] **Step 2: 验证编译**

Run: `swift build 2>&1 | tail -20`
Expected: 编译错误出现在 HTTPServer.swift、ConfigWindow.swift、MappingDetailView.swift 等（引用旧 mapping.apiProvider/baseURL 的地方），这是预期内的，后续 Task 修复。

- [ ] **Step 3: Commit**

```bash
git add APIBypass/Core/ConfigManager.swift
git commit -m "feat: extend ConfigManager with providers management and migration"
```

---

### Task 4: 修复 HTTPServer 代理逻辑

**Files:**
- Modify: `APIBypass/Core/HTTPServer.swift`

- [ ] **Step 1: 修改 handleProxyRequest 方法，通过 providerConfigId 获取提供商信息**

替换获取 API Key 的部分（原 `mapping.id.uuidString` → `mapping.providerConfigId.uuidString`），替换 `mapping.baseURL` → `provider.baseURL`，替换 `mapping.apiProvider` → `provider.apiProvider`。

在 `guard let mapping = configManager.findMapping(for: model)` 之后，新增：

```swift
// 获取提供商配置
guard let provider = configManager.findProvider(for: mapping.providerConfigId) else {
    let errorData = #"{"error": "Provider not found for this mapping"}"#.data(using: .utf8)!
    return Response(
        status: .badRequest,
        body: .init(byteBuffer: ByteBuffer(data: errorData))
    )
}
```

将 API Key 获取改为：
```swift
apiKey = try keychain.retrieve(forKey: mapping.providerConfigId.uuidString)
```

将 `mapping.baseURL` 改为 `provider.baseURL`（在构建上游 URL 部分）。
将 `mapping.apiProvider` 改为 `provider.apiProvider`（在 buildRequest 调用中）。

完整替换的 handleProxyRequest 方法关键部分：

```swift
// 解析模型名称 + 获取映射
guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let model = json["model"] as? String,
      let mapping = configManager.findMapping(for: model) else {
    let errorData = #"{"error": "Model not found or no mapping configured"}"#.data(using: .utf8)!
    return Response(
        status: .badRequest,
        body: .init(byteBuffer: ByteBuffer(data: errorData))
    )
}

// 获取提供商配置
guard let provider = configManager.findProvider(for: mapping.providerConfigId) else {
    let errorData = #"{"error": "Provider not found for this mapping"}"#.data(using: .utf8)!
    return Response(
        status: .badRequest,
        body: .init(byteBuffer: ByteBuffer(data: errorData))
    )
}

// ...（中间不变）

// 获取 API Key（通过 provider id）
let apiKey: String
do {
    apiKey = try keychain.retrieve(forKey: mapping.providerConfigId.uuidString)
} catch {
    let errorData = #"{"error": "API key not configured"}"#.data(using: .utf8)!
    return Response(
        status: .internalServerError,
        body: .init(byteBuffer: ByteBuffer(data: errorData))
    )
}

// 构建上游请求 URL（使用 provider.baseURL）
let upstreamURL: URL
let baseURLString = provider.baseURL.absoluteString

if baseURLString.hasSuffix("/v1") || baseURLString.hasSuffix("/v1/") {
    let endpointPath = format == .openai ? "chat/completions" : "messages"
    upstreamURL = provider.baseURL.appendingPathComponent(endpointPath)
} else {
    let endpoint = format == .openai ? "/v1/chat/completions" : "/v1/messages"
    upstreamURL = provider.baseURL.appendingPathComponent(endpoint)
}

let upstreamRequest = networkService.buildRequest(
    url: upstreamURL,
    method: "POST",
    body: transformedData,
    apiKey: apiKey,
    provider: provider.apiProvider,
    customHeaders: mapping.parameters.customHeaders
)
```

- [ ] **Step 2: 验证编译**

Run: `swift build 2>&1 | tail -20`
Expected: HTTPServer 编译错误已修复。剩余错误在 UI 文件中。

- [ ] **Step 3: Commit**

```bash
git add APIBypass/Core/HTTPServer.swift
git commit -m "feat: update HTTPServer to use provider from ConfigManager"
```

---

### Task 5: 新增 UI 视图 — ProviderDetailView

**Files:**
- Create: `APIBypass/UI/Views/ProviderDetailView.swift`

- [ ] **Step 1: 创建 ProviderDetailView**

提供商详情编辑视图，包含名称、类型、baseURL、API Key 编辑和删除按钮。

```swift
import SwiftUI

struct ProviderDetailView: View {
    @ObservedObject var configManager: ConfigManager
    let providerId: UUID
    let keychain: KeychainService

    var onHasChangesChange: ((Bool) -> Void)?
    var onSave: (() -> Void)?
    var forceResetTrigger: Int = 0
    var saveTrigger: Int = 0

    @ObservedObject private var l10n = LocalizationManager.shared

    @State private var name: String = ""
    @State private var apiProvider: APIProvider = .openai
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var showSaveConfirmation = false
    @State private var showDeleteConfirmation = false

    @State private var originalName: String = ""
    @State private var originalApiProvider: APIProvider = .openai
    @State private var originalBaseURL: String = ""
    @State private var originalApiKey: String = ""
    @State private var lastResetTrigger = 0
    @State private var lastSaveTrigger = 0

    private var hasChanges: Bool {
        name != originalName
            || apiProvider != originalApiProvider
            || baseURL != originalBaseURL
            || apiKey != originalApiKey
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("provider_info"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        HStack {
                            Text(L10n.t("provider_name"))
                                .frame(width: 100, alignment: .trailing)
                            TextField(L10n.t("provider_name_placeholder"), text: $name)
                        }
                        HStack {
                            Text(L10n.t("api_provider"))
                                .frame(width: 100, alignment: .trailing)
                            Picker("", selection: $apiProvider) {
                                Text("OpenAI").tag(APIProvider.openai)
                                Text("Anthropic").tag(APIProvider.anthropic)
                            }
                            .pickerStyle(.menu)
                            .onChange(of: apiProvider) { _, newValue in
                                if baseURL.isEmpty || baseURL == newValue.defaultBaseURL.absoluteString {
                                    baseURL = newValue.defaultBaseURL.absoluteString
                                }
                            }
                        }
                        HStack {
                            Text(L10n.t("base_url"))
                                .frame(width: 100, alignment: .trailing)
                            TextField(L10n.t("base_url_placeholder"), text: $baseURL)
                        }
                        HStack {
                            Text(L10n.t("api_key"))
                                .frame(width: 100, alignment: .trailing)
                            SecureField(L10n.t("api_key_placeholder"), text: $apiKey)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 关联的模型映射
                let relatedMappings = configManager.mappingsForProvider(providerId)
                if !relatedMappings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.t("related_mappings"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ForEach(relatedMappings) { mapping in
                            HStack {
                                Circle()
                                    .fill(mapping.isEnabled ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(mapping.name)
                                    .font(.body)
                                Text(mapping.actualModel)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                Spacer()
            }
            .padding()
        }
        .toolbar {
            Spacer()
            Button(action: {
                saveChanges()
            }) {
                Text(L10n.t("save"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hasChanges ? Color.accentColor : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(hasChanges ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .foregroundColor(hasChanges ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!hasChanges)
        }
        .onAppear {
            loadProviderData()
        }
        .onChange(of: hasChanges) { _, newValue in
            onHasChangesChange?(newValue)
        }
        .onChange(of: forceResetTrigger) { _, newValue in
            if newValue != lastResetTrigger {
                lastResetTrigger = newValue
                loadProviderData()
            }
        }
        .onChange(of: saveTrigger) { _, newValue in
            if newValue != lastSaveTrigger && hasChanges {
                lastSaveTrigger = newValue
                saveChanges()
            }
        }
        .alert(L10n.t("saved"), isPresented: $showSaveConfirmation) {
            Button(L10n.t("ok"), role: .cancel) {
                loadOriginalData()
            }
        }
    }

    private func loadProviderData() {
        guard let provider = configManager.findProvider(for: providerId) else { return }
        name = provider.name
        apiProvider = provider.apiProvider
        baseURL = provider.baseURL.absoluteString

        if let key = try? keychain.retrieve(forKey: providerId.uuidString) {
            apiKey = key
        }

        loadOriginalData()
    }

    private func loadOriginalData() {
        originalName = name
        originalApiProvider = apiProvider
        originalBaseURL = baseURL
        originalApiKey = apiKey
        onHasChangesChange?(false)
    }

    private func saveChanges() {
        guard let provider = configManager.findProvider(for: providerId) else { return }

        let updatedProvider = ProviderConfig(
            id: provider.id,
            name: name,
            apiProvider: apiProvider,
            baseURL: URL(string: baseURL) ?? apiProvider.defaultBaseURL
        )

        configManager.updateProvider(updatedProvider)

        if !apiKey.isEmpty {
            try? keychain.save(apiKey, forKey: providerId.uuidString)
        }

        onSave?()
        showSaveConfirmation = true
    }

    func discardChanges() {
        loadProviderData()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add APIBypass/UI/Views/ProviderDetailView.swift
git commit -m "feat: add ProviderDetailView"
```

---

### Task 6: 新增 UI 视图 — NewProviderView

**Files:**
- Create: `APIBypass/UI/Views/NewProviderView.swift`

- [ ] **Step 1: 创建 NewProviderView**

新建提供商的 Sheet 视图。同时支持从映射详情内联调用（创建后自动回调选中新 provider）。

```swift
import SwiftUI

struct NewProviderView: View {
    let configManager: ConfigManager
    let keychain: KeychainService
    var onCreated: ((ProviderConfig) -> Void)? = nil

    @Environment(\.dismiss) var dismiss
    @ObservedObject private var l10n = LocalizationManager.shared

    @State private var name = ""
    @State private var apiProvider: APIProvider = .openai
    @State private var baseURL = ""
    @State private var apiKey = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.t("new_provider"))
                .font(.headline)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("provider_info"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    HStack {
                        Text(L10n.t("provider_name"))
                            .frame(width: 100, alignment: .trailing)
                        TextField(L10n.t("provider_name_placeholder"), text: $name)
                    }
                    HStack {
                        Text(L10n.t("api_provider"))
                            .frame(width: 100, alignment: .trailing)
                        Picker("", selection: $apiProvider) {
                            Text("OpenAI").tag(APIProvider.openai)
                            Text("Anthropic").tag(APIProvider.anthropic)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: apiProvider) { _, newValue in
                            baseURL = newValue.defaultBaseURL.absoluteString
                        }
                    }
                    HStack {
                        Text(L10n.t("base_url"))
                            .frame(width: 100, alignment: .trailing)
                        TextField(L10n.t("base_url_placeholder"), text: $baseURL)
                    }
                    HStack {
                        Text(L10n.t("api_key"))
                            .frame(width: 100, alignment: .trailing)
                        SecureField(L10n.t("api_key_placeholder"), text: $apiKey)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            HStack {
                Button(L10n.t("cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.t("create")) {
                    createProvider()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || apiKey.isEmpty)
            }
            .padding(.bottom, 8)
        }
        .padding()
        .frame(width: 450, height: 320)
        .onAppear {
            if name.isEmpty {
                name = apiProvider == .openai ? "OpenAI" : "Anthropic"
            }
            baseURL = apiProvider.defaultBaseURL.absoluteString
        }
    }

    private func createProvider() {
        let provider = ProviderConfig(
            name: name,
            apiProvider: apiProvider,
            baseURL: URL(string: baseURL) ?? apiProvider.defaultBaseURL
        )

        configManager.addProvider(provider)
        try? keychain.save(apiKey, forKey: provider.id.uuidString)
        onCreated?(provider)
        dismiss()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add APIBypass/UI/Views/NewProviderView.swift
git commit -m "feat: add NewProviderView"
```

---

### Task 7: 修改 MappingDetailView — 提供商下拉选择

**Files:**
- Modify: `APIBypass/UI/Views/MappingDetailView.swift`

- [ ] **Step 1: 替换 apiProvider/baseURL/apiKey 为提供商下拉选择**

主要修改：

1. 移除 `@State private var apiProvider`、`@State private var baseURL`、`@State private var apiKey`
2. 新增 `@State private var selectedProviderId: UUID?` 和 `@State private var showNewProviderSheet = false`
3. 在基本信息区域，将 apiProvider Picker + baseURL TextField + apiKey SecureField 替换为提供商下拉选择
4. 变更检测改用 selectedProviderId
5. 保存时使用 selectedProviderId 构建 ModelMapping
6. 加载时从 mapping.providerConfigId 初始化 selectedProviderId

替换基本信息区域的 UI 代码：

```swift
// 替换原来的 apiProvider/baseURL/apiKey 部分
VStack(spacing: 8) {
    HStack {
        Text(L10n.t("config_name"))
            .frame(width: 100, alignment: .trailing)
        TextField(L10n.t("config_name_placeholder"), text: $name)
    }
    HStack {
        Text(L10n.t("incoming_model"))
            .frame(width: 100, alignment: .trailing)
        TextField(L10n.t("incoming_model_field"), text: $incomingModel)
    }
    HStack {
        Text(L10n.t("actual_model"))
            .frame(width: 100, alignment: .trailing)
        TextField(L10n.t("actual_model_field"), text: $actualModel)
    }
    HStack {
        Text(L10n.t("provider"))
            .frame(width: 100, alignment: .trailing)
        Picker("", selection: $selectedProviderId) {
            ForEach(configManager.providers) { provider in
                Text(provider.name).tag(provider.id as UUID?)
            }
        }
        .pickerStyle(.menu)

        Button {
            showNewProviderSheet = true
        } label: {
            Image(systemName: "plus.circle")
        }
        .buttonStyle(.plain)
    }

    // 提供商无效警告
    if let pid = selectedProviderId,
       configManager.findProvider(for: pid) == nil {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(L10n.t("provider_deleted_warning"))
                .font(.caption)
                .foregroundColor(.red)
        }
        .padding(.leading, 108)
    }

    // 显示当前提供商信息（只读）
    if let pid = selectedProviderId,
       let provider = configManager.findProvider(for: pid) {
        HStack {
            Text("")
                .frame(width: 100, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(provider.apiProvider.rawValue) · \(provider.baseURL.host ?? provider.baseURL.absoluteString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
```

需要额外新增的状态变量：
```swift
@State private var selectedProviderId: UUID?
@State private var originalProviderId: UUID?
@State private var showNewProviderSheet = false
```

修改 hasChanges 计算：
```swift
private var hasChanges: Bool {
    guard let original = originalMapping else { return false }
    if name != original.name { return true }
    if incomingModel != original.incomingModel { return true }
    if actualModel != original.actualModel { return true }
    if selectedProviderId != original.providerConfigId { return true }
    if isEnabled != original.isEnabled { return true }
    // ... 参数部分保持不变
    return false
}
```

修改 saveChanges：
```swift
private func saveChanges() {
    guard let mapping = configManager.mappings.first(where: { $0.id == mappingId }),
          let providerId = selectedProviderId else { return }

    let updatedMapping = ModelMapping(
        id: mapping.id,
        name: name,
        incomingModel: incomingModel,
        actualModel: actualModel,
        providerConfigId: providerId,
        parameters: buildParameters(),
        isEnabled: isEnabled
    )

    configManager.update(updatedMapping)
    onSave?()
    showSaveConfirmation = true
}
```

修改 loadMappingData：
```swift
private func loadMappingData() {
    guard let mapping = configManager.mappings.first(where: { $0.id == mappingId }) else { return }

    name = mapping.name
    incomingModel = mapping.incomingModel
    actualModel = mapping.actualModel
    selectedProviderId = mapping.providerConfigId
    isEnabled = mapping.isEnabled

    // ... 参数加载保持不变

    loadOriginalData()
}
```

修改 loadOriginalData：
```swift
private func loadOriginalData() {
    originalMapping = configManager.mappings.first(where: { $0.id == mappingId })
    originalProviderId = selectedProviderId
    onHasChangesChange?(false)
}
```

添加 Sheet：
```swift
.sheet(isPresented: $showNewProviderSheet) {
    NewProviderView(configManager: configManager, keychain: keychain) { newProvider in
        selectedProviderId = newProvider.id
    }
}
```

注意：思考模式中的 `apiProvider == .anthropic` 条件需要改为从 provider 获取：
```swift
if thinkingEnabled, let pid = selectedProviderId,
   let provider = configManager.findProvider(for: pid),
   provider.apiProvider == .anthropic {
```

- [ ] **Step 2: 验证编译**

Run: `swift build 2>&1 | tail -20`
Expected: MappingDetailView 编译错误已修复

- [ ] **Step 3: Commit**

```bash
git add APIBypass/UI/Views/MappingDetailView.swift
git commit -m "feat: update MappingDetailView to use provider selection"
```

---

### Task 8: 修改 MappingListView — 更新显示

**Files:**
- Modify: `APIBypass/UI/Views/MappingListView.swift`

- [ ] **Step 1: 更新列表显示**

MappingListView 中 `mapping.apiProvider` 字段已不存在。更新列表项，通过 `configManager.findProvider(for:)` 获取提供商名称显示：

```swift
import SwiftUI

struct MappingListView: View {
    @ObservedObject var configManager: ConfigManager
    @Binding var selectedMappingId: UUID?
    @ObservedObject private var l10n = LocalizationManager.shared

    var onCopy: ((ModelMapping) -> Void)?
    var onDelete: ((ModelMapping) -> Void)?

    var body: some View {
        List(selection: $selectedMappingId) {
            ForEach(configManager.mappings) { mapping in
                HStack {
                    Circle()
                        .fill(mapping.isEnabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading) {
                        Text(mapping.name)
                            .font(.headline)
                        let providerName = configManager.findProvider(for: mapping.providerConfigId)?.name ?? L10n.t("provider_missing")
                        Text("\(mapping.incomingModel) → \(mapping.actualModel) · \(providerName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .tag(mapping.id)
                .contextMenu {
                    Button {
                        onCopy?(mapping)
                    } label: {
                        Label(L10n.t("copy_config"), systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive) {
                        onDelete?(mapping)
                    } label: {
                        Label(L10n.t("delete_config"), systemImage: "trash")
                    }
                }
            }
        }
        .frame(minWidth: 200)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add APIBypass/UI/Views/MappingListView.swift
git commit -m "feat: update MappingListView to show provider name"
```

---

### Task 9: 重构 ConfigWindow — 分组列表

**Files:**
- Modify: `APIBypass/UI/ConfigWindow.swift`

这是最复杂的 UI 修改。需要将左侧列表改为提供商和映射两个分组，并管理两组选中状态。

- [ ] **Step 1: 重写 ConfigWindow**

核心变化：
1. 新增 `selectedProviderId` 状态
2. 左侧列表分为"提供商"和"模型映射"两个 Section
3. 添加/删除提供商按钮
4. 删除映射时不再删除 keychain（API Key 现在属于 provider）
5. 复制映射时使用 providerConfigId 替代 apiProvider/baseURL
6. 新建映射 Sheet 传递 configManager（内部已含 providers）
7. keychain preload 改为 provider ids

```swift
import SwiftUI

struct ConfigWindow: View {
    @ObservedObject var configManager: ConfigManager
    @State private var selectedMappingId: UUID?
    @State private var selectedProviderId: UUID?
    @State private var showNewMappingSheet = false
    @State private var showNewProviderSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showDeleteProviderConfirmation = false
    @State private var mappingToDelete: ModelMapping?
    @State private var providerToDelete: ProviderConfig?

    // 变更追踪
    @State private var currentHasChanges = false
    @State private var pendingSelection: SelectionTarget?
    @State private var targetSelection: SelectionTarget?
    @State private var showSwitchConfirmation = false
    @State private var forceResetTrigger = 0
    @State private var saveAndSwitchTrigger = 0

    @ObservedObject private var l10n = LocalizationManager.shared
    private let keychain = KeychainService.shared

    enum SelectionTarget: Equatable {
        case provider(UUID)
        case mapping(UUID)
    }

    var body: some View {
        NavigationSplitView {
            VStack {
                List {
                    // 提供商分组
                    Section(L10n.t("providers")) {
                        ForEach(configManager.providers) { provider in
                            HStack {
                                Image(systemName: provider.apiProvider == .openai ? "building.2" : "brain")
                                    .foregroundColor(.accentColor)
                                    .frame(width: 16)
                                VStack(alignment: .leading) {
                                    Text(provider.name)
                                        .font(.headline)
                                    Text(provider.baseURL.host ?? provider.baseURL.absoluteString)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .tag(SelectionTarget.provider(provider.id))
                            .contextMenu {
                                Button(role: .destructive) {
                                    providerToDelete = provider
                                    showDeleteProviderConfirmation = true
                                } label: {
                                    Label(L10n.t("delete_provider"), systemImage: "trash")
                                }
                            }
                        }
                    }

                    // 模型映射分组
                    Section(L10n.t("model_mappings")) {
                        ForEach(configManager.mappings) { mapping in
                            HStack {
                                Circle()
                                    .fill(mapping.isEnabled ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading) {
                                    Text(mapping.name)
                                        .font(.headline)
                                    let providerName = configManager.findProvider(for: mapping.providerConfigId)?.name ?? L10n.t("provider_missing")
                                    Text("\(mapping.incomingModel) → \(mapping.actualModel) · \(providerName)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .tag(SelectionTarget.mapping(mapping.id))
                            .contextMenu {
                                Button {
                                    copyMapping(mapping)
                                } label: {
                                    Label(L10n.t("copy_config"), systemImage: "doc.on.doc")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    mappingToDelete = mapping
                                    showDeleteConfirmation = true
                                } label: {
                                    Label(L10n.t("delete_config"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 220)

                HStack {
                    Button {
                        showNewProviderSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help(L10n.t("add_provider"))

                    Button {
                        showNewMappingSheet = true
                    } label: {
                        Image(systemName: "plus.square")
                    }
                    .help(L10n.t("add_mapping"))

                    Spacer()

                    Button {
                        deleteSelected()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help(L10n.t("delete_selected"))
                    .disabled(currentSelection == nil)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("APIBypass")
            .alert(L10n.t("confirm_delete_mapping"), isPresented: $showDeleteConfirmation) {
                Button(L10n.t("cancel"), role: .cancel) {
                    mappingToDelete = nil
                }
                Button(L10n.t("delete"), role: .destructive) {
                    if let mapping = mappingToDelete {
                        configManager.delete(mapping.id)
                        if selectedMappingId == mapping.id {
                            selectedMappingId = nil
                        }
                    }
                    mappingToDelete = nil
                }
            } message: {
                if let mapping = mappingToDelete {
                    Text("\(L10n.t("confirm_delete_msg"))「\(mapping.name)」\(L10n.t("confirm_delete_hint"))")
                } else {
                    Text(L10n.t("confirm_delete_generic"))
                }
            }
            .alert(L10n.t("confirm_delete_provider"), isPresented: $showDeleteProviderConfirmation) {
                Button(L10n.t("cancel"), role: .cancel) {
                    providerToDelete = nil
                }
                Button(L10n.t("delete"), role: .destructive) {
                    if let provider = providerToDelete {
                        let relatedCount = configManager.mappingsForProvider(provider.id).count
                        if relatedCount > 0 {
                            // 有关联映射，删除提供商后映射变无效
                        }
                        configManager.deleteProvider(provider.id)
                        try? keychain.delete(forKey: provider.id.uuidString)
                        if selectedProviderId == provider.id {
                            selectedProviderId = nil
                        }
                    }
                    providerToDelete = nil
                }
            } message: {
                if let provider = providerToDelete {
                    let count = configManager.mappingsForProvider(provider.id).count
                    if count > 0 {
                        Text("\(L10n.t("confirm_delete_provider_msg"))「\(provider.name)」\(L10n.t("confirm_delete_provider_hint_prefix"))\(count)\(L10n.t("confirm_delete_provider_hint_suffix"))")
                    } else {
                        Text("\(L10n.t("confirm_delete_msg"))「\(provider.name)」\(L10n.t("confirm_delete_hint"))")
                    }
                } else {
                    Text(L10n.t("confirm_delete_generic"))
                }
            }
            .alert(L10n.t("unsaved_changes"), isPresented: $showSwitchConfirmation) {
                Button(L10n.t("cancel"), role: .cancel) {
                    pendingSelection = nil
                }
                Button(L10n.t("discard_changes"), role: .destructive) {
                    if let newSelection = pendingSelection {
                        currentHasChanges = false
                        applySelection(newSelection)
                        forceResetTrigger += 1
                    }
                    pendingSelection = nil
                }
                Button(L10n.t("save_and_switch")) {
                    if let newSelection = pendingSelection {
                        targetSelection = newSelection
                        saveAndSwitchTrigger += 1
                    }
                    pendingSelection = nil
                }
            } message: {
                Text(L10n.t("unsaved_changes_msg"))
            }
        } detail: {
            detailView
        }
        .sheet(isPresented: $showNewProviderSheet) {
            NewProviderView(configManager: configManager, keychain: keychain) { newProvider in
                selectedProviderId = newProvider.id
                selectedMappingId = nil
            }
        }
        .sheet(isPresented: $showNewMappingSheet) {
            NewMappingView(configManager: configManager, keychain: keychain)
        }
        .onAppear {
            let providerIds = configManager.providers.map { $0.id.uuidString }
            keychain.preloadKeys(for: providerIds)
        }
    }

    // MARK: - Selection Management

    private var currentSelection: SelectionTarget? {
        if let pid = selectedProviderId {
            return .provider(pid)
        }
        if let mid = selectedMappingId {
            return .mapping(mid)
        }
        return nil
    }

    private func applySelection(_ target: SelectionTarget) {
        switch target {
        case .provider(let id):
            selectedProviderId = id
            selectedMappingId = nil
        case .mapping(let id):
            selectedMappingId = id
            selectedProviderId = nil
        }
    }

    private func deleteSelected() {
        if let pid = selectedProviderId,
           let provider = configManager.findProvider(for: pid) {
            providerToDelete = provider
            showDeleteProviderConfirmation = true
        } else if let mid = selectedMappingId,
                  let mapping = configManager.mappings.first(where: { $0.id == mid }) {
            mappingToDelete = mapping
            showDeleteConfirmation = true
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if let pid = selectedProviderId,
           configManager.findProvider(for: pid) != nil {
            ProviderDetailView(
                configManager: configManager,
                providerId: pid,
                keychain: keychain,
                onHasChangesChange: { hasChanges in
                    currentHasChanges = hasChanges
                },
                onSave: {
                    currentHasChanges = false
                    if let newSelection = targetSelection {
                        applySelection(newSelection)
                        targetSelection = nil
                    }
                },
                forceResetTrigger: forceResetTrigger,
                saveTrigger: saveAndSwitchTrigger
            )
            .id(pid)
        } else if let mappingId = selectedMappingId,
                  configManager.mappings.contains(where: { $0.id == mappingId }) {
            MappingDetailView(
                configManager: configManager,
                mappingId: mappingId,
                keychain: keychain,
                onHasChangesChange: { hasChanges in
                    currentHasChanges = hasChanges
                },
                onSave: {
                    currentHasChanges = false
                    if let newSelection = targetSelection {
                        applySelection(newSelection)
                        targetSelection = nil
                    }
                },
                forceResetTrigger: forceResetTrigger,
                saveTrigger: saveAndSwitchTrigger
            )
            .id(mappingId)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text(L10n.t("select_or_create"))
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text(L10n.t("select_or_create_hint"))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 16) {
                    Button {
                        showNewProviderSheet = true
                    } label: {
                        Label(L10n.t("create_provider"), systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showNewMappingSheet = true
                    } label: {
                        Label(L10n.t("create_new_config"), systemImage: "plus.square")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    // MARK: - Copy Mapping

    private func copyMapping(_ mapping: ModelMapping) {
        let newMapping = ModelMapping(
            name: mapping.name + " 副本",
            incomingModel: mapping.incomingModel,
            actualModel: mapping.actualModel,
            providerConfigId: mapping.providerConfigId,
            parameters: mapping.parameters,
            isEnabled: mapping.isEnabled
        )

        configManager.add(newMapping)
        selectedMappingId = newMapping.id
        selectedProviderId = nil
    }
}
```

- [ ] **Step 2: 修改 NewMappingView**

NewMappingView 需要改为使用提供商选择替代 apiProvider/baseURL/apiKey：

```swift
struct NewMappingView: View {
    let configManager: ConfigManager
    let keychain: KeychainService
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var l10n = LocalizationManager.shared

    @State private var name = "New Config"
    @State private var incomingModel = ""
    @State private var actualModel = ""
    @State private var selectedProviderId: UUID?
    @State private var showNewProviderSheet = false

    // 参数设置（保持不变）
    @State private var temperature = ""
    @State private var maxTokens = ""
    @State private var topP = ""
    @State private var frequencyPenalty = ""
    @State private var presencePenalty = ""
    @State private var thinkingEnabled = false
    @State private var thinkingBudget = ""
    @State private var thinkingOverrideEnabled = false

    @State private var customFields: [CustomField] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(L10n.t("new_model_mapping"))
                    .font(.headline)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("basic_info"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        HStack {
                            Text(L10n.t("config_name"))
                                .frame(width: 100, alignment: .trailing)
                            TextField(L10n.t("config_name_placeholder"), text: $name)
                        }
                        HStack {
                            Text(L10n.t("incoming_model"))
                                .frame(width: 100, alignment: .trailing)
                            TextField(L10n.t("incoming_model_placeholder"), text: $incomingModel)
                        }
                        HStack {
                            Text(L10n.t("actual_model"))
                                .frame(width: 100, alignment: .trailing)
                            TextField(L10n.t("actual_model_placeholder"), text: $actualModel)
                        }
                        HStack {
                            Text(L10n.t("provider"))
                                .frame(width: 100, alignment: .trailing)
                            Picker("", selection: $selectedProviderId) {
                                Text(L10n.t("select_provider")).tag(nil as UUID?)
                                ForEach(configManager.providers) { provider in
                                    Text(provider.name).tag(provider.id as UUID?)
                                }
                            }
                            .pickerStyle(.menu)

                            Button {
                                showNewProviderSheet = true
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.plain)
                        }

                        if let pid = selectedProviderId,
                           let provider = configManager.findProvider(for: pid) {
                            HStack {
                                Text("")
                                    .frame(width: 100, alignment: .trailing)
                                Text("\(provider.apiProvider.rawValue) · \(provider.baseURL.host ?? provider.baseURL.absoluteString)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 参数注入区域
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("param_injection"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        HStack {
                            Text("Temperature")
                                .frame(width: 120, alignment: .trailing)
                            TextField(L10n.t("temp_placeholder"), text: $temperature)
                        }
                        HStack {
                            Text("Max Tokens")
                                .frame(width: 120, alignment: .trailing)
                            TextField(L10n.t("max_tokens_placeholder"), text: $maxTokens)
                        }
                        HStack {
                            Text("Top P")
                                .frame(width: 120, alignment: .trailing)
                            TextField(L10n.t("top_p_placeholder"), text: $topP)
                        }
                        HStack {
                            Text("Frequency Penalty")
                                .frame(width: 120, alignment: .trailing)
                            TextField(L10n.t("freq_penalty_placeholder"), text: $frequencyPenalty)
                        }
                        HStack {
                            Text("Presence Penalty")
                                .frame(width: 120, alignment: .trailing)
                            TextField(L10n.t("pres_penalty_placeholder"), text: $presencePenalty)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 思考模式（保持不变，但判断 anthropic 改为从 provider 获取）
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.t("reasoning_override"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Toggle("", isOn: $thinkingOverrideEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    VStack(spacing: 8) {
                        HStack {
                            Toggle(L10n.t("enable_thinking"), isOn: $thinkingEnabled)
                                .disabled(!thinkingOverrideEnabled)
                            Spacer()
                        }
                        if thinkingEnabled,
                           let pid = selectedProviderId,
                           let provider = configManager.findProvider(for: pid),
                           provider.apiProvider == .anthropic {
                            HStack {
                                Text(L10n.t("thinking_budget"))
                                    .frame(width: 120, alignment: .trailing)
                                TextField(L10n.t("thinking_budget_hint"), text: $thinkingBudget)
                                    .disabled(!thinkingOverrideEnabled)
                                Text(L10n.t("thinking_budget_eg"))
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                    .opacity(thinkingOverrideEnabled ? 1.0 : 0.4)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 自定义参数（保持不变）
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.t("custom_params"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            customFields.append(CustomField(key: "", value: ""))
                        }) {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                    }

                    if customFields.isEmpty {
                        Text(L10n.t("add_custom_hint"))
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(customFields.indices, id: \.self) { index in
                                HStack {
                                    TextField(L10n.t("field_name_placeholder"), text: $customFields[index].key)
                                        .frame(width: 120)
                                    TextField(L10n.t("field_value_placeholder"), text: $customFields[index].value)
                                    Button(action: {
                                        customFields.remove(at: index)
                                    }) {
                                        Image(systemName: "minus.circle")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Text(L10n.t("custom_hint"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                HStack {
                    Button(L10n.t("cancel")) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(L10n.t("create")) {
                        createMapping()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(incomingModel.isEmpty || actualModel.isEmpty || selectedProviderId == nil)
                }
                .padding(.bottom, 8)
            }
            .padding()
        }
        .frame(width: 500, height: 700)
        .sheet(isPresented: $showNewProviderSheet) {
            NewProviderView(configManager: configManager, keychain: keychain) { newProvider in
                selectedProviderId = newProvider.id
            }
        }
    }

    private func createMapping() {
        guard let providerId = selectedProviderId else { return }

        let mapping = ModelMapping(
            name: name,
            incomingModel: incomingModel,
            actualModel: actualModel,
            providerConfigId: providerId,
            parameters: buildParameters()
        )

        configManager.add(mapping)
        dismiss()
    }

    private func buildParameters() -> InjectedParameters {
        let temp = Double(temperature)
        let tokens = Int(maxTokens)
        let topPValue = Double(topP)
        let freqPenalty = Double(frequencyPenalty)
        let presPenalty = Double(presencePenalty)

        let thinking: ThinkingConfig? = {
            guard thinkingOverrideEnabled else { return nil }
            return ThinkingConfig(
                enabled: thinkingEnabled,
                budgetTokens: thinkingEnabled ? Int(thinkingBudget) : nil
            )
        }()

        let customFieldsDict: [String: String]? = customFields.isEmpty
            ? nil
            : Dictionary(uniqueKeysWithValues: customFields.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) })

        return InjectedParameters(
            temperature: temp,
            maxTokens: tokens,
            topP: topPValue,
            frequencyPenalty: freqPenalty,
            presencePenalty: presPenalty,
            thinking: thinking,
            customFields: customFieldsDict
        )
    }
}
```

注意：`HRow` 在 NewMappingView 参数区域中是简化写法，实际实现应保持原来的 `HStack { Text(...) TextField(...) }` 格式，与 MappingDetailView 保持一致。

- [ ] **Step 3: 验证编译**

Run: `swift build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add APIBypass/UI/ConfigWindow.swift
git commit -m "feat: restructure ConfigWindow with provider/mapping split layout"
```

---

### Task 10: 新增 i18n key

**Files:**
- Modify: `APIBypass/Core/LocalizationManager.swift`

- [ ] **Step 1: 在 L10n.dict 中添加新的 key**

需要新增的 key：

```swift
// 提供商相关
"providers": [.chinese: "提供商", .english: "Providers"],
"provider_info": [.chinese: "提供商信息", .english: "Provider Info"],
"provider_name": [.chinese: "名称", .english: "Name"],
"provider_name_placeholder": [.chinese: "例如：我的 OpenAI", .english: "e.g. My OpenAI"],
"new_provider": [.chinese: "新建提供商", .english: "New Provider"],
"add_provider": [.chinese: "添加提供商", .english: "Add Provider"],
"add_new_provider": [.chinese: "➕ 添加新提供商...", .english: "➕ Add New Provider..."],
"delete_provider": [.chinese: "删除提供商", .english: "Delete Provider"],
"create_provider": [.chinese: "新建提供商", .english: "Create Provider"],
"select_provider": [.chinese: "选择提供商...", .english: "Select Provider..."],
"provider": [.chinese: "提供商", .english: "Provider"],
"provider_missing": [.chinese: "提供商缺失", .english: "Provider Missing"],
"provider_deleted_warning": [.chinese: "提供商已删除，请重新选择", .english: "Provider deleted, please reselect"],

// 映射分组
"model_mappings": [.chinese: "模型映射", .english: "Model Mappings"],
"related_mappings": [.chinese: "关联的模型映射", .english: "Related Model Mappings"],

// 删除确认
"confirm_delete_mapping": [.chinese: "确认删除映射", .english: "Confirm Delete Mapping"],
"confirm_delete_provider": [.chinese: "确认删除提供商", .english: "Confirm Delete Provider"],
"confirm_delete_provider_msg": [.chinese: "确定要删除", .english: "Are you sure you want to delete"],
"confirm_delete_provider_hint_prefix": [.chinese: "？该提供商已被 ", .english: "? This provider is used by "],
"confirm_delete_provider_hint_suffix": [.chinese: " 个映射使用，删除后这些映射将失效", .english: " mapping(s). They will become invalid after deletion"],

// 其他
"delete_selected": [.chinese: "删除选中项", .english: "Delete Selected"],
```

- [ ] **Step 2: Commit**

```bash
git add APIBypass/Core/LocalizationManager.swift
git commit -m "feat: add i18n keys for provider config feature"
```

---

### Task 11: 更新 APIBypassApp keychain 预加载

**Files:**
- Modify: `APIBypass/APIBypassApp.swift`

- [ ] **Step 1: 更新 keychain 预加载为 provider ids**

ConfigWindow 中已处理了 preload（`.onAppear` 中用 `configManager.providers.map { $0.id.uuidString }`），APIBypassApp 中无需额外修改。确认 APIBypassApp 中没有直接引用 mapping.apiProvider 或 keychain preload 的代码。

如果 APIBypassApp 中没有 keychain 预加载逻辑，此步可跳过。

- [ ] **Step 2: Commit**（仅在有实际修改时）

```bash
git add APIBypass/APIBypassApp.swift
git commit -m "feat: update keychain preload for provider-based keys"
```

---

### Task 12: 清理和验证

- [ ] **Step 1: 全量编译验证**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: 全文搜索旧字段引用**

Run: `grep -rn 'mapping\.apiProvider\|mapping\.baseURL\|\.apiProvider\b.*defaultBaseURL' APIBypass/ --include="*.swift"`
Expected: 无结果

- [ ] **Step 3: 运行应用手动验证**

1. 启动应用
2. 如果有旧配置数据，验证自动迁移（提供商自动创建，API Key 正确关联）
3. 添加新提供商 → 添加新映射 → 选择提供商 → 保存
4. 启动代理服务 → 发送请求验证代理正常工作
5. 删除有关联映射的提供商 → 验证确认弹窗 → 验证映射显示无效状态
6. 新建映射时点击"添加新提供商" → 验证内联创建流程

- [ ] **Step 4: Commit**（仅在有实际修改时）

```bash
git add -A
git commit -m "chore: cleanup after provider config refactoring"
```

---

### Task 13: 版本号和 Release Notes

- [ ] **Step 1: 更新版本号**

在 `APIBypass/UI/SettingsView.swift` 中更新版本号为 `0.4.0`

- [ ] **Step 2: 更新 RELEASE_NOTES.md**

新增 v0.4.0 release notes

- [ ] **Step 3: Commit**

```bash
git add APIBypass/UI/SettingsView.swift RELEASE_NOTES.md
git commit -m "release: v0.4.0 - provider config feature"
```
