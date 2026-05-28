import Foundation

struct EnvironmentVariableConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var value: String
    var type: EnvVarType
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        value: String,
        type: EnvVarType,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.type = type
        self.isEnabled = isEnabled
    }
}

enum EnvVarType: String, Codable, CaseIterable {
    case manual
    case modelMapping
    case keychainToken
    case baseURL

    var localizedName: String {
        switch self {
        case .manual:
            return L10n.t("envVar.type.manual")
        case .modelMapping:
            return L10n.t("envVar.type.modelMapping")
        case .keychainToken:
            return L10n.t("envVar.type.keychainToken")
        case .baseURL:
            return L10n.t("envVar.type.baseURL")
        }
    }
}
