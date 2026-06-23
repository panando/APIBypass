import Foundation

struct StreamingResult: Sendable {
    let response: URLResponse
    let bytes: URLSession.AsyncBytes
}

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
        case .openai, .responses:
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

    /// 发送请求并返回流式响应
    func sendStream(request: URLRequest) async throws -> StreamingResult {
        let (bytes, response) = try await session.bytes(for: request)

        // 检查 HTTP 状态码
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            // 非 2xx 响应，读取错误信息
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            throw ProxyError.upstreamError(
                (response as? HTTPURLResponse)?.statusCode ?? 500,
                errorData
            )
        }

        return StreamingResult(response: response, bytes: bytes)
    }
}
