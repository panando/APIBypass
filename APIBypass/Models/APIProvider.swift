import Foundation

enum APIProvider: String, Codable, CaseIterable {
    case openai
    case anthropic

    var defaultBaseURL: URL {
        switch self {
        case .openai:
            return URL(string: "https://api.openai.com")!
        case .anthropic:
            return URL(string: "https://api.anthropic.com")!
        }
    }
}
