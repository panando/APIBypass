import Foundation

/// Persistence layer for CodexAdaptorConfig using UserDefaults.
actor CodexAdaptorConfigStore {
    static let shared = CodexAdaptorConfigStore()

    private let userDefaultsKey = "com.apibypass.codexAdaptor"
    private var cached: CodexAdaptorConfig?

    private init() {}

    func load() -> CodexAdaptorConfig {
        if let cached { return cached }
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(CodexAdaptorConfig.self, from: data) else {
            let defaultConfig = CodexAdaptorConfig()
            cached = defaultConfig
            return defaultConfig
        }
        cached = config
        return config
    }

    func save(_ config: CodexAdaptorConfig) {
        cached = config
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
