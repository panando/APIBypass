import Foundation

/// User-facing model catalog configuration for Codex providers.
/// This matches cc-switch's settings.modelCatalog structure.
public struct ModelCatalog: Codable, Equatable {
    public var models: [ModelCatalogEntry]

    public init(models: [ModelCatalogEntry] = []) {
        self.models = models
    }
}

/// A single model entry in the user's catalog configuration.
/// Fields match cc-switch's expected input format:
/// - model: required (the model slug/id)
/// - displayName / display_name: optional (defaults to model if not set)
/// - contextWindow / context_window: optional (defaults to model_context_window or 128000)
public struct ModelCatalogEntry: Codable, Identifiable, Equatable {
    public var id: String { model }

    /// The model slug/id (required)
    public var model: String
    /// Display name (optional, defaults to model)
    public var displayName: String?
    /// Context window size (optional)
    public var contextWindow: UInt64?

    public init(
        model: String,
        displayName: String? = nil,
        contextWindow: UInt64? = nil
    ) {
        self.model = model
        self.displayName = displayName
        self.contextWindow = contextWindow
    }

    enum CodingKeys: String, CodingKey {
        case model
        case displayName
        case contextWindow
        // Also support snake_case variants for compatibility
        case display_name
        case context_window
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        // Try both camelCase and snake_case
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .display_name)
        contextWindow = try container.decodeIfPresent(UInt64.self, forKey: .contextWindow)
            ?? container.decodeIfPresent(UInt64.self, forKey: .context_window)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        // Use camelCase for output (cc-switch accepts both)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(contextWindow, forKey: .contextWindow)
    }
}
