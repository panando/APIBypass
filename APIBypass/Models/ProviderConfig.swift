import Foundation

struct ProviderConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var apiProvider: APIProvider
    var baseURL: URL
    var environmentVariables: [EnvironmentVariableConfig] = []

    init(
        id: UUID = UUID(),
        name: String,
        apiProvider: APIProvider,
        baseURL: URL,
        environmentVariables: [EnvironmentVariableConfig] = []
    ) {
        self.id = id
        self.name = name
        self.apiProvider = apiProvider
        self.baseURL = baseURL
        self.environmentVariables = environmentVariables
    }

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
                name: "ANTHROPIC_AUTH_TOKEN",
                value: "",
                type: .keychainToken,
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
                name: "ANTHROPIC_DEFAULT_OPUS_MODEL",
                value: "",
                type: .manual,
                isEnabled: true
            ),
            EnvironmentVariableConfig(
                id: UUID(),
                name: "ANTHROPIC_DEFAULT_SONNET_MODEL",
                value: "",
                type: .manual,
                isEnabled: true
            ),
            EnvironmentVariableConfig(
                id: UUID(),
                name: "ANTHROPIC_DEFAULT_HAIKU_MODEL",
                value: "",
                type: .manual,
                isEnabled: true
            ),
            EnvironmentVariableConfig(
                id: UUID(),
                name: "CLAUDE_CODE_SUBAGENT_MODEL",
                value: "",
                type: .manual,
                isEnabled: true
            ),
            EnvironmentVariableConfig(
                id: UUID(),
                name: "CLAUDE_CODE_EFFORT_LEVEL",
                value: "max",
                type: .manual,
                isEnabled: true
            )
        ]
    }
}
