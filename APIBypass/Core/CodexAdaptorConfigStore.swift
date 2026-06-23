import Foundation
import CodexRouterCore

/// Persistence layer for CodexAdaptorConfig using UserDefaults.
/// Falls back to reading ~/.codex/providers.json when UserDefaults has no stored config.
actor CodexAdaptorConfigStore {
    static let shared = CodexAdaptorConfigStore()

    private let userDefaultsKey = "com.apibypass.codexAdaptor"
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
        // No UserDefaults config — try recovery from providers.json
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
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
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
