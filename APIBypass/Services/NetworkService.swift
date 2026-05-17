import Foundation

final class NetworkService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func buildRequest(
        url: URL,
        method: String,
        body: Data,
        apiKey: String,
        provider: APIProvider,
        customHeaders: [String: String]? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 根据提供商设置认证头
        switch provider {
        case .openai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        // 注入自定义 headers
        customHeaders?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    func send(request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
