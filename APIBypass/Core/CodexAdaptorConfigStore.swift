import Foundation
import CodexRouterCore

/// Persistence layer for CodexAdaptorConfig.
///
/// Primary store: UserDefaults (key `com.apibypass.codexAdaptor`).
/// Mirror store: `~/.codex/apibypass-config.json` — survives app reinstall (UserDefaults
/// are wiped on reinstall, but `~/.codex/` is not). On load, if UserDefaults is empty
/// we read the mirror file before falling back to `recoverFromProvidersJSON`.
actor CodexAdaptorConfigStore {
    static let shared = CodexAdaptorConfigStore()

    private let userDefaultsKey = "com.apibypass.codexAdaptor"
    private let mirrorFileName = "apibypass-config.json"
    private var cached: CodexAdaptorConfig?
    private var didAttemptRecovery = false

    private init() {}

    func load() async -> CodexAdaptorConfig {
        if let cached { return cached }
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let config = try? JSONDecoder().decode(CodexAdaptorConfig.self, from: data) {
            cached = config
            return config
        }
        // UserDefaults empty (e.g. after app reinstall) — try the mirror file in
        // ~/.codex/, which is preserved across reinstalls.
        if let config = loadFromMirrorFile() {
            cached = config
            // Re-populate UserDefaults so subsequent loads skip the mirror.
            if let data = try? JSONEncoder().encode(config) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            }
            return config
        }
        // No mirror file — try recovery from providers.json as a last resort.
        if !didAttemptRecovery, let recovered = await recoverFromProvidersJSON() {
            cached = recovered
            didAttemptRecovery = true
            return recovered
        }
        let defaultConfig = CodexAdaptorConfig()
        cached = defaultConfig
        return defaultConfig
    }

    func save(_ config: CodexAdaptorConfig) {
        cached = config
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
        // Mirror to ~/.codex/apibypass-config.json so the config survives app reinstalls.
        let dir = NSHomeDirectory() + "/.codex"
        let path = dir + "/" + mirrorFileName
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true)
        }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func loadFromMirrorFile() -> CodexAdaptorConfig? {
        let path = NSHomeDirectory() + "/.codex/" + mirrorFileName
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(CodexAdaptorConfig.self, from: data)
    }

    // MARK: - Recovery from providers.json

    private func recoverFromProvidersJSON() async -> CodexAdaptorConfig? {
        let providersPath = NSHomeDirectory() + "/.codex/providers.json"
        guard FileManager.default.fileExists(atPath: providersPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: providersPath)) else {
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = json["providers"] as? [String: Any],
              let meta = providers["apibypass"] as? [String: Any] else {
            return nil
        }

        var config = CodexAdaptorConfig()

        // Recover wire API
        if let wireAPI = meta["upstreamWireAPI"] as? String {
            config.wireAPI = CodexAdaptorConfig.WireAPI(rawValue: wireAPI) ?? .chat
        }

        // Recover reasoning config
        if let reasoningDict = meta["reasoningConfig"] as? [String: Any],
           let reasoningData = try? JSONSerialization.data(withJSONObject: reasoningDict),
           let reasoningConfig = try? JSONDecoder().decode(ReasoningConfig.self, from: reasoningData) {
            config.reasoningConfig = reasoningConfig
            config.reasoningOverrideEnabled = true
        }

        // Recover custom models from model catalog
        if let catalog = meta["modelCatalog"] as? [String: Any],
           let models = catalog["models"] as? [[String: Any]] {
            let mappings = await ConfigDataStore.shared.getMappings()
            config.customModels = models.compactMap { entry -> CustomModelEntry? in
                guard let slug = entry["model"] as? String else { return nil }
                guard let mapping = mappings.first(where: { $0.incomingModel == slug }) else {
                    return nil
                }
                let alias = entry["displayName"] as? String ?? slug
                let contextWindow = entry["contextWindow"] as? UInt64 ?? 128000
                return CustomModelEntry(
                    alias: alias,
                    modelMappingId: mapping.id,
                    contextWindow: contextWindow
                )
            }
            // Migrate legacy customModels to protocol-specific lists
            config.migrateFromLegacy()
        }

        // Persist recovered config so future loads hit UserDefaults
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }

        return config
    }
}
