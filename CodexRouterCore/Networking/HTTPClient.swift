import Foundation
import Hummingbird
import HTTPTypes

private enum HTTPClientError: Error {
    case invalidURL
    case invalidResponse
}

/// HTTP client for making requests to upstream API providers.
public final class HTTPClient: Sendable {

    public init() {}

    /// Send a request to an upstream provider.
    public func send(
        url: String,
        method: HTTPRequest.Method,
        headers: [String: String],
        body: Data?
    ) async throws -> (Data, HTTPResponse.Status) {
        guard let url = URL(string: url) else {
            throw HTTPClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 600

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }

        let status = HTTPResponse.Status(integerLiteral: httpResponse.statusCode)
        return (data, status)
    }

    /// Send a streaming request and return an async sequence of data chunks.
    public func sendStreaming(
        url: String,
        method: HTTPRequest.Method,
        headers: [String: String],
        body: Data?
    ) async throws -> StreamingResponse {
        guard let url = URL(string: url) else {
            throw HTTPClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 1200

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = body {
            request.httpBody = body
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }

        let status = HTTPResponse.Status(integerLiteral: httpResponse.statusCode)
        return StreamingResponse(status: status, asyncBytes: asyncBytes)
    }
}

/// Streaming response that provides an async sequence of SSE events.
public struct StreamingResponse: Sendable {
    public let status: HTTPResponse.Status
    private let asyncBytes: URLSession.AsyncBytes

    init(status: HTTPResponse.Status, asyncBytes: URLSession.AsyncBytes) {
        self.status = status
        self.asyncBytes = asyncBytes
    }

    /// Returns an async sequence that yields complete SSE events.
    /// Handles both \n\n and \r\n\r\n delimiters (following cc-switch's approach).
    public var events: AsyncStream<Data> {
        AsyncStream { continuation in
            Task {
                var buffer = Data()
                do {
                    for try await byte in asyncBytes {
                        buffer.append(byte)

                        // Check for SSE event boundaries (both \n\n and \r\n\r\n)
                        if buffer.count >= 4 {
                            let lastFour = buffer.suffix(4)
                            if lastFour == Data([0x0D, 0x0A, 0x0D, 0x0A]) { // \r\n\r\n
                                let event = buffer.dropLast(4)
                                if !event.isEmpty {
                                    continuation.yield(Data(event))
                                }
                                buffer.removeAll(keepingCapacity: true)
                            }
                        }

                        if buffer.count >= 2 {
                            let lastTwo = buffer.suffix(2)
                            if lastTwo == Data([0x0A, 0x0A]) { // \n\n
                                // Only if not already handled by \r\n\r\n
                                if buffer.count >= 4 {
                                    let lastFour = buffer.suffix(4)
                                    if lastFour == Data([0x0D, 0x0A, 0x0D, 0x0A]) {
                                        continue // Already handled above
                                    }
                                }
                                let event = buffer.dropLast(2)
                                if !event.isEmpty {
                                    continuation.yield(Data(event))
                                }
                                buffer.removeAll(keepingCapacity: true)
                            }
                        }
                    }

                    // Send any remaining data
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }
}

