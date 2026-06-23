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
}
