import Foundation

enum APIProvider: String, Codable, CaseIterable {
    case openai
    case anthropic
    case openaiResponses

    var defaultBaseURL: URL {
        switch self {
        case .openai:
            return URL(string: "https://api.openai.com")!
        case .anthropic:
            return URL(string: "https://api.anthropic.com")!
        case .openaiResponses:
            return URL(string: "https://api.openai.com")!
        }
    }

    /// 实际使用的 HTTP 请求格式（Responses 在传输层仍使用 OpenAI 的 Bearer 认证）
    var transportFormat: APIProvider {
        switch self {
        case .openaiResponses:
            return .openai
        default:
            return self
        }
    }
}
