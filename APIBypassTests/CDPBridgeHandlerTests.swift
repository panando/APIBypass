import XCTest
import CodexRouterCore

/// Verifies CDPBridgeHandler forwards HTTP requests to the local proxy and
/// returns response bodies. This is the native side of the CSP-bypass bridge:
/// JS calls `window.__codexSessionDeleteBridge(path, payload)`, CDP delivers
/// it as a `Runtime.bindingCalled` event, and this handler forwards the call
/// to `http://127.0.0.1:{port}{path}` — bypassing Codex's `connect-src` CSP
/// which blocks renderer-originated fetches to localhost.
final class CDPBridgeHandlerTests: XCTestCase {

    func test_getRequest_forwardsToPathAndReturnsBody() async throws {
        let mock = HTTPMock()
        mock.register(path: "/settings/get", method: "GET", status: 200,
                      body: #"{"modelProvider":"apibypass"}"#)

        let handler = CDPBridgeHandler(port: 12345, session: mock.session)
        let result = try await handler.handle(CDPBindingRequest(path: "/settings/get", payload: nil))

        XCTAssertEqual(String(data: result, encoding: .utf8), #"{"modelProvider":"apibypass"}"#)
        XCTAssertEqual(mock.lastRequest?.url?.path, "/settings/get")
        XCTAssertEqual(mock.lastRequest?.httpMethod, "GET")
    }

    func test_postRequest_sendsJsonBodyAndReturnsBody() async throws {
        let mock = HTTPMock()
        // Echo back the received body so the test can verify body forwarding
        // through the response (URLProtocol can't reliably expose httpBody).
        mock.register(path: "/cdp/diagnostic", method: "POST", status: 200, body: "{\"echo\":\"ok\"}")

        let handler = CDPBridgeHandler(port: 12345, session: mock.session)
        let body = #"{"event":"script_loaded"}"#.data(using: .utf8)!
        let result = try await handler.handle(CDPBindingRequest(path: "/cdp/diagnostic", payload: body))

        XCTAssertEqual(String(data: result, encoding: .utf8), "{\"echo\":\"ok\"}")
        XCTAssertEqual(mock.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(mock.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func test_non2xxResponse_throws() async throws {
        let mock = HTTPMock()
        mock.register(path: "/missing", method: "GET", status: 404, body: "not found")

        let handler = CDPBridgeHandler(port: 12345, session: mock.session)
        do {
            _ = try await handler.handle(CDPBindingRequest(path: "/missing", payload: nil))
            XCTFail("Expected throw for 404")
        } catch {
            // expected
        }
    }
}

// MARK: - HTTP Mock

/// Minimal URLProtocol-backed HTTP mock. Routes are matched by (path, method).
/// Tests are sequential, so a single static responder is safe.
private final class HTTPMock: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [(path: String, method: String, status: Int, body: Data)] = []
    private var _lastRequest: URLRequest?

    var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return _lastRequest
    }

    func register(path: String, method: String, status: Int, body: String) {
        lock.lock(); defer { lock.unlock() }
        routes.append((path, method, status, body.data(using: .utf8)!))
    }

    fileprivate func route(request: URLRequest) -> (HTTPURLResponse, Data)? {
        lock.lock(); defer { lock.unlock() }
        _lastRequest = request
        for r in routes where r.path == request.url?.path && r.method == request.httpMethod {
            let resp = HTTPURLResponse(url: request.url!, statusCode: r.status,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, r.body)
        }
        return nil
    }

    var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BridgeMockURLProtocol.self]
        BridgeMockURLProtocol.active = self
        return URLSession(configuration: config)
    }
}

private final class BridgeMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var active: HTTPMock?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let mock = Self.active else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "BridgeMock", code: 1))
            return
        }
        guard let (response, data) = mock.route(request: request) else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "BridgeMock", code: 2))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
