import Foundation
import CodexRouterCore

/// Configuration for the Codex Adaptor feature, persisted in APIBypass's UserDefaults.
struct CodexAdaptorConfig: Codable, Equatable {
    var port: Int = 15721
    var wireAPI: WireAPI = .chat
    var reasoningOverrideEnabled: Bool = false
    var reasoningConfig: ReasoningConfig?

    // Legacy field - kept for migration compatibility
    var customModels: [CustomModelEntry] = []

    // New fields: protocol-specific model lists
    var chatCustomModels: [CustomModelEntry] = []
    var responsesCustomModels: [CustomModelEntry] = []

    var cdpSettings: CDPInjectionSettings = CDPInjectionSettings()
    var cdpDebugPort: UInt16 = 9222

    /// Verbose logging mode: when true, logs all events; when false, only errors and non-duplicate events.
    var verboseLogging: Bool = true

    /// Convenience accessor for the current protocol's model list
    var currentCustomModels: [CustomModelEntry] {
        get { wireAPI == .chat ? chatCustomModels : responsesCustomModels }
        set {
            if wireAPI == .chat { chatCustomModels = newValue }
            else { responsesCustomModels = newValue }
        }
    }

    /// Migrate from legacy customModels to protocol-specific lists
    mutating func migrateFromLegacy() {
        // Only migrate if new fields are empty and legacy has data
        guard chatCustomModels.isEmpty && responsesCustomModels.isEmpty else { return }
        guard !customModels.isEmpty else { return }

        // Migrate to chatCustomModels (default assumption for existing configs)
        chatCustomModels = customModels
    }

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
