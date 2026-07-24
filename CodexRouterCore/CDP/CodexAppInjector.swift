import Foundation

/// High-level orchestrator for Codex app CDP injection.
/// Discovers the Codex debug page, connects via CDP, injects JavaScript,
/// and monitors for page reloads.
public actor CodexAppInjector {
    public var settings: CDPInjectionSettings
    private let debugPort: UInt16
    private var client: CDPClient?
    private var isRunning = false
    private var monitorTask: Task<Void, Never>?
    private var injectedPageId: String?
    private let logger: CDPLogger?
    private var connectionState: CDPConnectionState = .disconnected

    private static let httpTimeout: TimeInterval = 3
    private static let monitorInterval: TimeInterval = 3
    /// Fast poll interval used while waiting for a new Codex page to reappear
    /// after the previous page disappeared (quit/restart). Keeps re-injection
    /// latency under the 2s spec target; restored to `monitorInterval` once a
    /// new page is injected.
    private static let reconnectMonitorInterval: TimeInterval = 0.4

    /// Poll interval for a given connection state. Stable states (connected /
    /// injected) use the slow 3s interval; reconnecting states use the fast
    /// 400ms interval so a new Codex page is re-injected within 2s of the
    /// previous page disappearing. Pure function - safe to unit-test.
    public static func monitorInterval(for state: CDPConnectionState) -> TimeInterval {
        switch state {
        case .connected, .injected:
            return monitorInterval
        default:
            return reconnectMonitorInterval
        }
    }
    private static let httpSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    public init(debugPort: UInt16 = 9222, settings: CDPInjectionSettings = CDPInjectionSettings(), logger: CDPLogger? = nil) {
        self.debugPort = debugPort
        self.settings = settings
        self.logger = logger
    }

    /// Read-only accessor for the configured debug port.
    public var configuredDebugPort: UInt16 { debugPort }

    /// Start injection. Connects to Codex debug port and injects JS.
    public func start() async {
        guard !isRunning else { return }
        isRunning = true
        await injectIntoCodex()
        startMonitor()
    }

    /// Stop injection and disconnect.
    public func stop() async {
        isRunning = false
        monitorTask?.cancel()
        monitorTask = nil
        await client?.disconnect()
        client = nil
        injectedPageId = nil
        connectionState = .disconnected
        logger?.logInfo("[CDP] Injector stopped")
    }

    /// Snapshot current connection state for UI polling.
    public func snapshotState() -> CDPConnectionState {
        return connectionState
    }

    /// Update settings and push to injected JS via postMessage.
    public func updateSettings(_ newSettings: CDPInjectionSettings) async {
        settings = newSettings
        guard client != nil else { return }
        try? await pushSettings()
    }

    // MARK: - Private

    private func injectIntoCodex() async {
        connectionState = .connecting
        logger?.logInfo("[CDP] Connecting to debug port :\(debugPort)")
        do {
            let targets = try await queryCDPTargets()
            guard let target = pickCodexTarget(targets) else {
                connectionState = .disconnected
                logger?.logInfo("[CDP] No Codex page target found, will retry")
                return
            }

            guard let wsURLString = target.webSocketDebuggerUrl,
                  let wsURL = URL(string: wsURLString) else {
                connectionState = .failed("Invalid WebSocket URL")
                logger?.logError("[CDP] Invalid WebSocket URL for target")
                return
            }

            logger?.logInfo("[CDP] Connecting to WebSocket: \(wsURLString)")

            let cdpClient = CDPClient(wsURL: wsURL)
            try await cdpClient.connect()
            self.client = cdpClient
            self.injectedPageId = target.id
            connectionState = .connected
            logger?.logInfo("[CDP] WebSocket connected")

            // Install the CDP binding bridge before the injection script so
            // __codexSessionDeleteBridge is available when the script runs.
            // The bridge routes JS calls through a native CDP binding, bypassing
            // Codex's renderer CSP which blocks fetch() to localhost.
            let bridge = CDPBridgeHandler(port: settings.proxyPort)
            do {
                try await cdpClient.addBinding(name: cdpBridgeBindingName) { request in
                    try await bridge.handle(request)
                }
                try await cdpClient.addScriptToEvaluateOnNewDocument(cdpBridgeScript)
                _ = try await cdpClient.evaluateJavaScript(cdpBridgeScript)
                logger?.logInfo("[CDP] Bridge installed")
            } catch {
                logger?.logError("[CDP] Bridge installation failed: \(error.localizedDescription)")
            }

            do {
                try await pushSettings()
            } catch {
                logger?.logError("[CDP] Failed to push settings: \(error.localizedDescription)")
            }

            do {
                try await cdpClient.evaluateJavaScript(codexPluginInjectionScript)
                connectionState = .injected
                logger?.logInfo("[CDP] Script injected")
            } catch {
                connectionState = .failed(error.localizedDescription)
                logger?.logError("[CDP] Injection failed: \(error.localizedDescription)")
            }

        } catch {
            connectionState = .failed(error.localizedDescription)
            logger?.logError("[CDP] \(error.localizedDescription)")
        }
    }

    private func pushSettings() async throws {
        guard let client = client else { return }
        let jsonData = try JSONEncoder().encode(settings)
        let b64 = jsonData.base64EncodedString()
        let js = """
        (function() {
          try {
            var s = JSON.parse(atob('\(b64)'));
            window.__codexPlusBackendSettings = s;
            window.postMessage({ type: 'codexPlusSettingsUpdate', settings: s }, '*');
          } catch (e) {}
        })();
        """
        _ = try await client.evaluateJavaScript(js)
    }

    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self = self else { return }
            while true {
                if Task.isCancelled { break }
                let running = await self.isRunning
                if !running { break }
                do {
                    // Use nanoseconds API to avoid Swift Issue #86204 cross-module specialization crash.
                    // Fast-poll (400ms) while disconnected/reconnecting so a new page is re-injected
                    // within 2s of the previous page disappearing; 3s once stable.
                    let interval = Self.monitorInterval(for: await self.snapshotState())
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch is CancellationError {
                    break
                } catch {
                    // Ignore other errors
                }
                if Task.isCancelled { break }
                await self.monitorAndReinject()
            }
        }
    }

    private func monitorAndReinject() async {
        do {
            let targets = try await queryCDPTargets()
            if let currentId = injectedPageId {
                let stillExists = targets.contains(where: { $0.id == currentId })
                if !stillExists {
                    logger?.logInfo("[CDP] Page disappeared, reconnecting")
                    connectionState = .disconnected
                    await client?.disconnect()
                    client = nil
                    injectedPageId = nil
                    await injectIntoCodex()
                }
            } else {
                await injectIntoCodex()
            }
        } catch {
            // Codex was closed or debug port unavailable
            if connectionState != .disconnected {
                logger?.logInfo("[CDP] Connection lost: \(error.localizedDescription)")
                connectionState = .disconnected
            }
            await client?.disconnect()
            client = nil
            injectedPageId = nil
        }
    }

    // MARK: - CDP Target Discovery

    private func queryCDPTargets() async throws -> [CDPTarget] {
        let urls = CDPProbeURLs(port: debugPort)

        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, response) = try await Self.httpSession.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { continue }
                return try JSONDecoder().decode([CDPTarget].self, from: data)
            } catch {
                continue
            }
        }

        throw CDPError.noTargetsFound
    }

    private func pickCodexTarget(_ targets: [CDPTarget]) -> CDPTarget? {
        return CodexRouterCore.pickCodexTarget(targets)
    }

    // MARK: - Settings HTTP endpoint handler

    /// Handle a /settings/get request and return the current settings as JSON.
    public func handleSettingsGet() -> (status: Int, contentType: String, body: String) {
        let jsonData = (try? JSONEncoder().encode(settings)) ?? Data()
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            return (500, "application/json", #"{"error":"encode failed"}"#)
        }
        return (200, "application/json", jsonString)
    }

    /// Handle a POST /settings/update request.
    public func handleSettingsUpdate(_ body: Data) {
        guard let newSettings = try? JSONDecoder().decode(CDPInjectionSettings.self, from: body) else {
            return
        }
        settings = newSettings
    }
}

// MARK: - CDP Target Selection

/// Select the best CDP page target for injection.
///
/// Matching order:
/// 1. Page with "codex" in title or URL (backward compat with legacy Codex.app)
/// 2. ChatGPT desktop page: title == "chatgpt" (exact, case-insensitive) AND url in whitelist
/// 3. No match → nil (no fallback to first page)
public func pickCodexTarget(_ targets: [CDPTarget]) -> CDPTarget? {
    let pages = targets.filter { target in
        target.type == "page"
            && target.webSocketDebuggerUrl.map { !$0.isEmpty } ?? false
    }

    // Pass 1: Prefer a page with "codex" in title or URL (legacy)
    for target in pages {
        let haystack = "\(target.title) \(target.url)".lowercased()
        if haystack.contains("codex") {
            return target
        }
    }

    // Pass 2: ChatGPT desktop page (exact title + URL whitelist)
    for target in pages {
        if isChatGPTDesktopPage(title: target.title, url: target.url) {
            return target
        }
    }

    // No match — return nil instead of falling back to first page
    return nil
}

/// Check if a CDP target is a ChatGPT desktop page.
///
/// Title must be exactly "chatgpt" (case-insensitive) to avoid matching
/// extension pages like "ChatGPT for Chrome". URL must be in a known whitelist.
private func isChatGPTDesktopPage(title: String, url: String) -> Bool {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard normalizedTitle == "chatgpt" else { return false }

    let normalizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let knownPrefixes = [
        "https://chatgpt.com",
        "https://chat.openai.com",
        "data:text/html",
    ]
    return knownPrefixes.contains(where: { normalizedURL.hasPrefix($0) })
}
