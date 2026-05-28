import Foundation

struct ProviderConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var apiProvider: APIProvider
    var baseURL: URL
    var environmentVariables: [EnvironmentVariableConfig]

    init(
        id: UUID = UUID(),
        name: String,
        apiProvider: APIProvider,
        baseURL: URL,
        environmentVariables: [EnvironmentVariableConfig]? = nil
    ) {
        self.id = id
        self.name = name
        self.apiProvider = apiProvider
        self.baseURL = baseURL
        self.environmentVariables = environmentVariables ?? ProviderConfig.defaultEnvironmentVariables()
    }

    /// 预设的环境变量模板
    static func defaultEnvironmentVariables() -> [EnvironmentVariableConfig] {
        [
            EnvironmentVariableConfig(
                id: UUID(),
                name: "ANTHROPIC_BASE_URL",
                value: "",
                type: .baseURL,
                isEnabled: true
            ),
            EnvironmentVariableConfig(
                id: UUID(),
                name: "ANTHROPIC_MODEL",
                value: "",
                type: .modelMapping,
                isEnabled: true
            ),
            EnvironmentVariableConfig(
                id: UUID(),
                name: "ANTHROPIC_AUTH_TOKEN",
                value: "",
                type: .keychainToken,
                isEnabled: true
            )
        ]
    }
}
