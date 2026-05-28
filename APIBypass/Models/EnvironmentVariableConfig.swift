import Foundation

struct EnvironmentVariableConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var value: String
    var type: EnvVarType
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        value: String = "",
        type: EnvVarType = .manual,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.type = type
        self.isEnabled = isEnabled
    }

    enum EnvVarType: String, Codable, CaseIterable {
        case manual = "manual"
        case modelMapping = "model_mapping"
        case keychainToken = "keychain_token"
        case baseURL = "base_url"
    }
}
