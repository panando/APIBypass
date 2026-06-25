import Foundation
import Network
import Dispatch

/// Low-level CDP WebSocket client for communicating with a Codex app debug target.
///
/// Uses `NWConnection` + `NWProtocolWebSocket` rather than `URLSessionWebSocketTask`
/// because the latter never delivers frames from Chromium's DevTools server (handshake
/// completes but `receive()` never invokes its completion handler). `NWProtocolWebSocket`
/// gives us explicit control over the WS handshake headers (Origin) and matches the
/// behaviour of CPP's `tokio_tungstenite::connect_async`.
///
/// The receive path runs entirely on the transport `DispatchQueue` and dispatches
/// responses via a lock-protected `pendingMessages` map. This avoids hopping to the
/// actor's executor — which would deadlock because the actor is suspended inside
/// `sendCommand`'s `withCheckedThrowingContinuation` waiting for the very response
/// the receive path is trying to deliver.
public actor CDPClient {
    private let wsURL: URL
    private var connection: NWConnection?
    private var msgId: Int = 0
    private let dispatch: CDPMessageDispatch
    private var isConnected = false
    private let queue = DispatchQueue(label: "CDPClient.transport")
    private var bindingHandlers: [String: @Sendable (CDPBindingRequest) async throws -> Data] = [:]

    public init(wsURL: URL) {
        self.wsURL = wsURL
        self.dispatch = CDPMessageDispatch()
    }

    deinit {
        connection?.cancel()
    }

    public func connect() async throws {
        connection?.cancel()
        connection = nil
        msgId = 0
        dispatch.clearAll(with: CDPError.connectionFailed("Reconnecting"))
        isConnected = false

        guard let host = wsURL.host, let portInt = wsURL.port else {
            throw CDPError.connectionFailed("Invalid WebSocket URL: \(wsURL.absoluteString)")
        }
        let origin = CDPOriginHeader(for: wsURL) ?? "http://\(host):\(portInt)"

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsOptions.setAdditionalHeaders([(name: "Origin", value: origin)])

        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        // NWEndpoint.url carries the full path (e.g. /devtools/page/<id>) so the WS
        // upgrade request hits the right DevTools target. NWConnection(host:port:)
        // would default to `GET /`, which Chromium rejects.
        let conn = NWConnection(to: .url(wsURL), using: params)
        self.connection = conn

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate()
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if gate.tryResume() { cont.resume() }
                case .failed(let err):
                    if gate.tryResume() {
                        cont.resume(throwing: CDPError.connectionFailed("WebSocket failed: \(err)"))
                    } else {
                        self?.dispatch.clearAll(with: CDPError.connectionFailed("WebSocket failed: \(err)"))
                    }
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
        isConnected = true

        // Wire notification forwarder so bindingCalled events reach the actor.
        self.dispatch.setNotificationForwarder { [weak self] data in
            Task { await self?.handleNotification(data) }
        }

        // Wire the receive callback. The callback runs on `queue` and dispatches
        // responses directly via `CDPMessageDispatch` — no actor hop.
        let dispatch = self.dispatch
        conn.receiveMessage { [weak self] content, _, _, error in
            if let error = error {
                dispatch.clearAll(with: CDPError.connectionFailed("Receive failed: \(error)"))
                return
            }
            if let data = content {
                dispatch.handle(data)
            }
            // Re-arm the receive loop. Hop to the actor only to read `connection`.
            Task { await self?.receiveNext() }
        }

        _ = try await sendCommand(method: "Runtime.enable", params: nil)
    }

    public func disconnect() {
        isConnected = false
        connection?.cancel()
        connection = nil
        dispatch.clearAll(with: CDPError.connectionFailed("Disconnected"))
    }

    @discardableResult
    public func evaluateJavaScript(_ expression: String) async throws -> CDPEvaluationResult {
        // `awaitPromise: true` makes Runtime.evaluate resolve the returned promise
        // before returning — without it, an async-function expression returns
        // `{type: "object", subtype: "promise", value: {}}` (the un-resolved
        // Promise object), and callers see an empty object instead of the
        // resolved value. This matters for any JS expression that evaluates to
        // a Promise (e.g. `await fetch(...).then(r => r.json())`).
        let params: [String: Any] = [
            "expression": expression,
            "returnByValue": true,
            "awaitPromise": true,
        ]
        let result = try await sendCommand(method: "Runtime.evaluate", params: params)

        if let exception = result["exceptionDetails"] as? [String: Any] {
            let text = (exception["text"] as? String) ?? "Unknown error"
            let desc = (exception["exception"] as? [String: Any])?["description"] as? String ?? text
            throw CDPError.evaluationFailed(desc)
        }

        let value = result["result"] as? [String: Any]
        let raw = value?["value"]
        let str: String?
        if let s = raw as? String {
            str = s
        } else if let b = raw as? Bool {
            // NSJSONSerialization parses JSON `true`/`false` as NSNumber, which
            // bridges to Bool via `as? Bool`. Without this branch, `String(describing:)`
            // renders them as "1"/"0" (NSNumber description), breaking callers
            // that compare against "true"/"false".
            str = b ? "true" : "false"
        } else if let raw = raw {
            str = String(describing: raw)
        } else {
            str = nil
        }
        return CDPEvaluationResult(value: str, exceptionDetails: nil)
    }

    /// Registers a CDP binding that JS can call via `window.{name}(payload)`.
    ///
    /// When JS invokes the binding, CDP delivers a `Runtime.bindingCalled` event
    /// with the JS-provided payload string. CDPClient parses `{id, path, payload}`
    /// from that string, calls `handler` with a `CDPBindingRequest`, and evaluates
    /// `window.__codexSessionDeleteResolve(id, result)` in the renderer with the
    /// handler's return value. On handler failure, evaluates
    /// `window.__codexSessionDeleteReject(id, error)` instead.
    ///
    /// This bypasses Codex's renderer CSP (`connect-src` blocks localhost fetches)
    /// by running the HTTP call natively — no `fetch()` from the page.
    public func addBinding(
        name: String,
        handler: @escaping @Sendable (CDPBindingRequest) async throws -> Data
    ) async throws {
        bindingHandlers[name] = handler
        _ = try await sendCommand(method: "Runtime.addBinding", params: ["name": name])
    }

    /// Installs a script that runs on every new document (page load), surviving
    /// reloads. Used for the bridge script that defines `__codexSessionDeleteBridge`
    /// so the binding is available before any page JS runs.
    public func addScriptToEvaluateOnNewDocument(_ source: String) async throws {
        _ = try await sendCommand(
            method: "Page.addScriptToEvaluateOnNewDocument",
            params: ["source": source]
        )
    }

    /// Routes a raw CDP notification (method + params, no id) to the right handler.
    private func handleNotification(_ data: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else { return }
        let params = (json["params"] as? [String: Any]) ?? [:]

        if method == "Runtime.bindingCalled" {
            let name = params["name"] as? String ?? ""
            let payload = params["payload"] as? String ?? ""
            await handleBindingCalled(name: name, payload: payload)
        }
    }

    private func handleBindingCalled(name: String, payload: String) async {
        guard let handler = bindingHandlers[name] else { return }

        guard let payloadData = payload.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let id = parsed["id"] as? Int,
              let path = parsed["path"] as? String else {
            return
        }
        let innerPayload = (parsed["payload"] as? String)?.data(using: .utf8)
        let request = CDPBindingRequest(path: path, payload: innerPayload)

        do {
            let result = try await handler(request)
            await resolveBinding(id: id, result: result)
        } catch {
            await rejectBinding(id: id, error: error)
        }
    }

    private func resolveBinding(id: Int, result: Data) async {
        let resultString = String(data: result, encoding: .utf8) ?? ""
        guard let literal = jsStringLiteral(resultString) else { return }
        let js = "window.__codexSessionDeleteResolve(\(id), \(literal));"
        _ = try? await evaluateJavaScript(js)
    }

    private func rejectBinding(id: Int, error: Error) async {
        let message = String(describing: error)
        guard let literal = jsStringLiteral(message) else { return }
        let js = "window.__codexSessionDeleteReject(\(id), \(literal));"
        _ = try? await evaluateJavaScript(js)
    }

    /// Returns a JS string literal (quoted, escaped) for the given string, or nil on failure.
    private func jsStringLiteral(_ string: String) -> String? {
        guard let data = try? JSONEncoder().encode(string),
              let literal = String(data: data, encoding: .utf8) else {
            return nil
        }
        return literal
    }

    // MARK: - Private

    private func sendCommand(method: String, params: [String: Any]?) async throws -> [String: Any] {
        guard let conn = connection else {
            throw CDPError.connectionFailed("Not connected")
        }

        let id = msgId
        msgId += 1

        var dict: [String: Any] = ["id": id, "method": method]
        if let params = params {
            dict["params"] = params
        }

        let data = try JSONSerialization.data(withJSONObject: dict)

        return try await withCheckedThrowingContinuation { cont in
            dispatch.register(id: id, continuation: cont)
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "cdp-\(id)", metadata: [metadata])
            conn.send(content: data, contentContext: context, completion: .contentProcessed { [dispatch] error in
                guard let error = error else { return }
                dispatch.fail(id: id, with: CDPError.connectionFailed("Send failed: \(error)"))
            })
        }
    }

    /// Re-arm the receive loop. Called from the receive callback via a lightweight
    /// actor hop (after the response has already been dispatched).
    private func receiveNext() {
        guard isConnected, let conn = connection else { return }
        let dispatch = self.dispatch
        conn.receiveMessage { [weak self] content, _, _, error in
            if let error = error {
                dispatch.clearAll(with: CDPError.connectionFailed("Receive failed: \(error)"))
                return
            }
            if let data = content {
                dispatch.handle(data)
            }
            Task { await self?.receiveNext() }
        }
    }
}

/// Thread-safe dispatch of CDP responses to waiting continuations.
///
/// Lives outside the actor so the transport `DispatchQueue` can resume `sendCommand`
/// continuations without hopping to the actor — which would deadlock because the
/// actor is suspended inside `withCheckedThrowingContinuation` waiting for the
/// very response being dispatched.
private final class CDPMessageDispatch: @unchecked Sendable {
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var notificationForwarder: (@Sendable (Data) -> Void)?
    private let lock = NSLock()

    func register(id: Int, continuation: CheckedContinuation<[String: Any], Error>) {
        lock.lock()
        defer { lock.unlock() }
        pending[id] = continuation
    }

    func setNotificationForwarder(_ forwarder: @escaping @Sendable (Data) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        notificationForwarder = forwarder
    }

    func handle(_ data: Data) {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

        // Response to a command (has id).
        if let id = json["id"] as? Int {
            lock.lock()
            let cont = pending.removeValue(forKey: id)
            lock.unlock()
            guard let cont = cont else { return }

            if let error = json["error"] as? [String: Any] {
                let msg = (error["message"] as? String) ?? "CDP error"
                cont.resume(throwing: CDPError.evaluationFailed(msg))
            } else {
                cont.resume(returning: json["result"] as? [String: Any] ?? [:])
            }
            return
        }

        // Notification (has method, no id) — forward to the actor.
        if json["method"] as? String != nil {
            lock.lock()
            let forwarder = notificationForwarder
            lock.unlock()
            forwarder?(data)
        }
    }

    func fail(id: Int, with error: Error) {
        lock.lock()
        let cont = pending.removeValue(forKey: id)
        lock.unlock()
        cont?.resume(throwing: error)
    }

    func clearAll(with error: Error) {
        lock.lock()
        let all = pending
        pending.removeAll()
        lock.unlock()
        for (_, cont) in all {
            cont.resume(throwing: error)
        }
    }
}

/// One-shot gate ensuring a continuation is only resumed once across concurrent state callbacks.
private final class ContinuationGate: @unchecked Sendable {
    private var resumed = false
    private let lock = NSLock()

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}
