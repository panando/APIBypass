import Foundation

/// Low-level CDP WebSocket client for communicating with a Codex app debug target.
public actor CDPClient {
    private let wsURL: URL
    private var wsTask: URLSessionWebSocketTask?
    private var msgId: Int = 0
    private var pendingMessages: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var isConnected = false

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    public init(wsURL: URL) {
        self.wsURL = wsURL
    }

    deinit {
        wsTask?.cancel()
    }

    public func connect() async throws {
        wsTask?.cancel()
        msgId = 0
        clearPending(CDPError.connectionFailed("Reconnecting"))

        wsTask = Self.session.webSocketTask(with: wsURL)
        wsTask?.resume()

        // Kick off the receive loop
        Task { [weak self] in await self?.runReceiveLoop() }

        _ = try await sendCommand(method: "Runtime.enable", params: nil)
        isConnected = true
    }

    public func disconnect() {
        isConnected = false
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        clearPending(CDPError.connectionFailed("Disconnected"))
    }

    @discardableResult
    public func evaluateJavaScript(_ expression: String) async throws -> CDPEvaluationResult {
        let params: [String: Any] = ["expression": expression, "returnByValue": true]
        let result = try await sendCommand(method: "Runtime.evaluate", params: params)

        if let exception = result["exceptionDetails"] as? [String: Any] {
            let text = (exception["text"] as? String) ?? "Unknown error"
            let desc = (exception["exception"] as? [String: Any])?["description"] as? String ?? text
            throw CDPError.evaluationFailed(desc)
        }

        let value = result["result"] as? [String: Any]
        let str = value?["value"] as? String
        return CDPEvaluationResult(value: str, exceptionDetails: nil)
    }

    // MARK: - Private

    private func sendCommand(method: String, params: [String: Any]?) async throws -> [String: Any] {
        guard let task = wsTask else {
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
            pendingMessages[id] = cont
            Task {
                do {
                    try await task.send(.data(data))
                } catch {
                    pendingMessages.removeValue(forKey: id)
                    cont.resume(throwing: CDPError.connectionFailed(error.localizedDescription))
                }
            }
        }
    }

    private func runReceiveLoop() async {
        guard let task = wsTask else { return }
        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                handle(message)
            }
        } catch {
            isConnected = false
            clearPending(CDPError.connectionFailed("WebSocket closed: \(error.localizedDescription)"))
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let extractJSON = { () -> [String: Any]? in
            switch message {
            case .data(let data):
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            case .string(let text):
                guard let data = text.data(using: .utf8) else { return nil }
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            @unknown default:
                return nil
            }
        }

        guard let json = extractJSON(), let id = json["id"] as? Int else { return }
        guard let cont = pendingMessages.removeValue(forKey: id) else { return }

        if let error = json["error"] as? [String: Any] {
            let msg = (error["message"] as? String) ?? "CDP error"
            cont.resume(throwing: CDPError.evaluationFailed(msg))
        } else {
            cont.resume(returning: json["result"] as? [String: Any] ?? [:])
        }
    }

    private func clearPending(_ error: Error) {
        for (_, cont) in pendingMessages {
            cont.resume(throwing: error)
        }
        pendingMessages.removeAll()
    }
}
