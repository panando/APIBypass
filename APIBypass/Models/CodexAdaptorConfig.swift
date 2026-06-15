import Foundation
import CodexRouterCore

/// Configuration for the Codex Adaptor feature, persisted in APIBypass's UserDefaults.
struct CodexAdaptorConfig: Codable, Equatable {
    var port: Int = 15721
    var wireAPI: WireAPI = .chat
    var reasoningOverrideEnabled: Bool = false
    var reasoningConfig: ReasoningConfig?
    var customModels: [CustomModelEntry] = []
    var cdpSettings: CDPInjectionSettings = CDPInjectionSettings()
    var cdpDebugPort: UInt16 = 9222

    enum WireAPI: String, Codable, CaseIterable {
        case chat = "chat"
        case responses = "responses"

        var displayName: String {
            switch self {
            case .chat: return "Chat Completions"
            case .responses: return "Responses API"
            }
        }
    }
}

/// A custom model entry mapping an alias to an APIBypass model mapping.
struct CustomModelEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var alias: String
    var modelMappingId: UUID
    var contextWindow: UInt64?
}
