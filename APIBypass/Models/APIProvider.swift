import Foundation

enum APIProvider: String, Codable, CaseIterable {
    case openai
    case anthropic
    case responses

    var defaultBaseURL: URL {
        switch self {
        case .openai:
            return URL(string: "https://api.openai.com")!
        case .anthropic:
            return URL(string: "https://api.anthropic.com")!
        case .responses:
            return URL(string: "https://api.openai.com")!  // 占位，用户需配置实际 URL
        }
    }

    var transportFormat: APIProvider {
        return self
    }

    /// 该 API 格式支持传输的参数集合
    var transportableParameters: Set<InjectedParameter> {
        switch self {
        case .openai:
            return [
                .temperature, .topP, .maxTokens,
                .frequencyPenalty, .presencePenalty,
                .reasoningEffort, .thinkingType, .thinkingBudget
            ]
        case .anthropic:
            return [
                .temperature, .topP, .topK, .maxTokens,
                .thinkingType, .budgetTokens
            ]
        case .responses:
            return [
                .temperature, .topP, .maxOutputTokens,
                .frequencyPenalty, .presencePenalty,
                .reasoningEffort, .thinkingType, .thinkingBudget
            ]
        }
    }
}
