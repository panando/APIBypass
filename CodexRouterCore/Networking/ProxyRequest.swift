import Foundation

/// Supported proxy endpoints.
public enum ProxyEndpoint: String, Sendable {
    case chatCompletions = "/v1/chat/completions"
    case responses = "/v1/responses"
    case responsesCompact = "/v1/responses/compact"
    case models = "/v1/models"
    case health = "/health"

    /// Returns the upstream path for this endpoint.
    /// The `/v1` prefix is excluded because it is already part of the provider's base URL.
    public func upstreamPath(usesChatCompletions: Bool) -> String {
        switch self {
        case .chatCompletions:
            return "/chat/completions"
        case .responses:
            if usesChatCompletions {
                return "/chat/completions"
            }
            return "/responses"
        case .responsesCompact:
            return "/responses/compact"
        case .models:
            return "/models"
        case .health:
            return "/health"
        }
    }
}
