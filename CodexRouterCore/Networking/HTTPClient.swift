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
                var eventCount = 0
                var totalBytes = 0
                var eventTypes: [String: Int] = [:]  // 统计各类型事件数量
                var maxEventSize = 0
                let startTime = Date()
                var firstEventTime: Date?

                // Helper: extract event type from SSE data
                func extractEventType(_ data: Data) -> String? {
                    guard let str = String(data: data, encoding: .utf8) else { return nil }
                    // Try to find "type":"xxx" in the data
                    if let typeRange = str.range(of: "\"type\":\"") {
                        let start = typeRange.upperBound
                        if let end = str.range(of: "\"", range: start..<str.endIndex) {
                            return String(str[start..<end.lowerBound])
                        }
                    }
                    // Check for [DONE]
                    if str.contains("[DONE]") { return "[DONE]" }
                    // Check for event: line
                    if let eventRange = str.range(of: "event: ") {
                        let start = eventRange.upperBound
                        if let end = str.range(of: "\n", range: start..<str.endIndex) {
                            return String(str[start..<end.lowerBound])
                        }
                    }
                    return nil
                }

                do {
                    for try await byte in asyncBytes {
                        buffer.append(byte)
                        totalBytes += 1

                        // Check for SSE event boundaries (both \n\n and \r\n\r\n)
                        if buffer.count >= 4 {
                            let lastFour = buffer.suffix(4)
                            if lastFour == Data([0x0D, 0x0A, 0x0D, 0x0A]) { // \r\n\r\n
                                let event = buffer.dropLast(4)
                                if !event.isEmpty {
                                    eventCount += 1
                                    if firstEventTime == nil { firstEventTime = Date() }

                                    // Track event type
                                    if let eventType = extractEventType(Data(event)) {
                                        eventTypes[eventType, default: 0] += 1
                                    }

                                    // Track max size
                                    if event.count > maxEventSize { maxEventSize = event.count }

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
                                    eventCount += 1
                                    if firstEventTime == nil { firstEventTime = Date() }

                                    // Track event type
                                    if let eventType = extractEventType(Data(event)) {
                                        eventTypes[eventType, default: 0] += 1
                                    }

                                    // Track max size
                                    if event.count > maxEventSize { maxEventSize = event.count }

                                    continuation.yield(Data(event))
                                }
                                buffer.removeAll(keepingCapacity: true)
                            }
                        }
                    }

                    // Send any remaining data
                    if !buffer.isEmpty {
                        eventCount += 1
                        if let eventType = extractEventType(buffer) {
                            eventTypes[eventType, default: 0] += 1
                        }
                        continuation.yield(buffer)
                    }

                    // Log comprehensive stats
                    let duration = Date().timeIntervalSince(startTime)
                    let timeToFirstEvent = firstEventTime.map { $0.timeIntervalSince(startTime) } ?? -1
                    print("[SSEParser] ✅ Stream finished: \(eventCount) events, \(totalBytes) bytes, \(String(format: "%.2f", duration))s")
                    print("[SSEParser] 📊 Time to first event: \(String(format: "%.2f", timeToFirstEvent))s, max event size: \(maxEventSize) bytes")
                    print("[SSEParser] 📈 Event types: \(eventTypes.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", "))")

                    // Check for critical events
                    if eventTypes["response.completed"] == nil && eventCount > 0 {
                        print("[SSEParser] ⚠️ WARNING: No response.completed event found!")
                    }
                    if eventTypes["[DONE]"] == nil && eventCount > 0 {
                        print("[SSEParser] ⚠️ WARNING: No [DONE] marker found!")
                    }
                    if eventTypes["response.failed"] != nil {
                        print("[SSEParser] ❌ ERROR: response.failed event detected!")
                    }

                    continuation.finish()
                } catch {
                    let duration = Date().timeIntervalSince(startTime)
                    print("[SSEParser] ❌ Stream error after \(String(format: "%.2f", duration))s: \(error)")
                    print("[SSEParser] 📊 Before error: \(eventCount) events, \(totalBytes) bytes received")
                    print("[SSEParser] 📈 Event types seen: \(eventTypes)")
                    continuation.finish()
                }
            }
        }
    }
}

