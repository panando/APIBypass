import Foundation

/// Supported proxy endpoints.
public enum ProxyEndpoint: String, Sendable {
    case chatCompletions = "/v1/chat/completions"
    case responses = "/v1/responses"
    case responsesCompact = "/v1/responses/compact"
    case models = "/v1/models"
    case health = "/health"

    /// Returns the upstream path for this endpoint.
    public func upstreamPath(usesChatCompletions: Bool) -> String {
        switch self {
        case .chatCompletions:
            return "/v1/chat/completions"
        case .responses:
            if usesChatCompletions {
                return "/v1/chat/completions"
            }
            return "/v1/responses"
        case .responsesCompact:
            return "/v1/responses/compact"
        case .models:
            return "/v1/models"
        case .health:
            return "/health"
        }
    }
}
