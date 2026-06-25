import Foundation

/// A bridge request forwarded from the renderer via CDP `Runtime.bindingCalled`.
///
/// JS calls `window.__codexSessionDeleteBridge(path, payload)`; the native side
/// receives `{id, path, payload}` and constructs this request. `id` is handled
/// by `CDPClient` (to route the response back to the correct JS promise); the
/// bridge handler only sees `path` and `payload`.
public struct CDPBindingRequest: Sendable {
    public let path: String
    public let payload: Data?

    public init(path: String, payload: Data?) {
        self.path = path
        self.payload = payload
    }
}

/// Forwards `CDPBindingRequest`s to the local Codex proxy HTTP server.
///
/// Codex's renderer CSP (`connect-src 'self' https://ab.chatgpt.com ...`)
/// blocks `fetch('http://127.0.0.1:15721/...')` from the page. This handler
/// runs in the native process (no CSP) and bridges the call — the JS side
/// invokes a CDP binding, the native side forwards to localhost, and the
/// response is returned to JS via `Runtime.evaluate`.
public struct CDPBridgeHandler: Sendable {
    public let port: Int
    public let session: URLSession

    public init(port: Int, session: URLSession = .shared) {
        self.port = port
        self.session = session
    }

    public func handle(_ request: CDPBindingRequest) async throws -> Data {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(request.path)") else {
            throw CDPError.connectionFailed("Invalid bridge URL for path: \(request.path)")
        }

        var urlRequest = URLRequest(url: url)
        let body = request.payload ?? Data()
        if request.payload != nil {
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else {
            urlRequest.httpMethod = "GET"
        }

        let (data, response) = try await session.upload(for: urlRequest, from: body)
        guard let http = response as? HTTPURLResponse else {
            throw CDPError.connectionFailed("Non-HTTP response from \(request.path)")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CDPError.evaluationFailed("Bridge HTTP \(http.statusCode) for \(request.path)")
        }
        return data
    }
}
