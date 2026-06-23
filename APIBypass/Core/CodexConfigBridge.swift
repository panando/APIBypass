import Foundation
import CodexRouterCore

/// A model mapping with its associated provider type.
struct MappingWithProvider: Identifiable, Equatable {
    let mapping: ModelMapping
    let providerType: APIProvider

    var id: UUID { mapping.id }
}

/// Bridges APIBypass's model mappings to CodexRouterCore's model catalog system.
@MainActor
struct CodexConfigBridge {
    /// Extract all available model names from APIBypass's ConfigManager for the dropdown.
    static func availableModelNames(from configManager: ConfigManager) -> [String] {
        configManager.mappings
            .filter { $0.isEnabled }
            .map { $0.incomingModel }
            .sorted()
    }

    /// Get all model mappings from APIBypass's ConfigManager.
    static func availableMappings(from configManager: ConfigManager) -> [ModelMapping] {
        configManager.mappings.filter { $0.isEnabled }
    }

    /// Get all model mappings with their provider type, grouped for UI display.
    static func availableMappingsWithProvider(from configManager: ConfigManager) -> [MappingWithProvider] {
        configManager.mappings
            .filter { $0.isEnabled }
            .compactMap { mapping in
                guard let provider = configManager.providers.first(where: { $0.id == mapping.providerConfigId }) else {
                    return nil
                }
                return MappingWithProvider(mapping: mapping, providerType: provider.apiProvider)
            }
    }

    /// Get model mappings filtered by protocol type.
    /// - Parameters:
    ///   - wireAPI: The protocol type to filter by (.chat or .responses)
    ///   - configManager: The ConfigManager to get mappings from
    /// - Returns: Model mappings that belong to providers of the specified protocol type
    static func availableMappings(for wireAPI: CodexAdaptorConfig.WireAPI, from configManager: ConfigManager) -> [ModelMapping] {
        let mappingsWithProvider = availableMappingsWithProvider(from: configManager)

        switch wireAPI {
        case .chat:
            // Chat protocol includes openai and anthropic providers
            return mappingsWithProvider
                .filter { $0.providerType != .responses }
                .map { $0.mapping }
        case .responses:
            // Responses protocol only includes responses providers
            return mappingsWithProvider
                .filter { $0.providerType == .responses }
                .map { $0.mapping }
        }
    }

    /// Resolve a CustomModelEntry to the actual model name via APIBypass's mappings.
    static func resolveModelName(entry: CustomModelEntry, configManager: ConfigManager) -> String? {
        configManager.mappings.first { $0.id == entry.modelMappingId }?.incomingModel
    }

    /// Build a ModelCatalog from custom model entries for Codex's model picker.
    static func buildModelCatalog(
        from entries: [CustomModelEntry],
        configManager: ConfigManager
    ) -> ModelCatalog {
        let catalogEntries = entries.compactMap { entry -> ModelCatalogEntry? in
            guard configManager.mappings.first(where: { $0.id == entry.modelMappingId }) != nil else {
                return nil
            }
            return ModelCatalogEntry(
                model: entry.alias,
                displayName: entry.alias,
                contextWindow: entry.contextWindow
            )
        }
        return ModelCatalog(models: catalogEntries)
    }
}
