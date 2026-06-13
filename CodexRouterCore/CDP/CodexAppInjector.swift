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

    private static let httpTimeout: TimeInterval = 3
    private static let monitorInterval: TimeInterval = 3
    private static let httpSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    public init(debugPort: UInt16 = 9222, settings: CDPInjectionSettings = CDPInjectionSettings()) {
        self.debugPort = debugPort
        self.settings = settings
    }

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
    }

    /// Update settings and push to injected JS via postMessage.
    public func updateSettings(_ newSettings: CDPInjectionSettings) async {
        settings = newSettings
        guard client != nil else { return }
        try? await pushSettings()
    }

    // MARK: - Private

    private func injectIntoCodex() async {
        do {
            // Find the Codex page target
            let targets = try await queryCDPTargets()
            guard let target = pickCodexTarget(targets) else {
                // No Codex page yet - will retry on monitor
                return
            }

            guard let wsURLString = target.webSocketDebuggerUrl,
                  let wsURL = URL(string: wsURLString) else {
                return
            }

            // Connect to CDP WebSocket
            let cdpClient = CDPClient(wsURL: wsURL)
            try await cdpClient.connect()
            self.client = cdpClient
            self.injectedPageId = target.id

            // Push current settings before injecting
            try? await pushSettings()

            // Inject the script
            try await cdpClient.evaluateJavaScript(codexPluginInjectionScript)

        } catch {
            // Will retry on monitor
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
                try? await Task.sleep(for: .seconds(Self.monitorInterval))
                if Task.isCancelled { break }
                await self.monitorAndReinject()
            }
        }
    }

    private func monitorAndReinject() async {
        // Check if the page is still there
        do {
            let targets = try await queryCDPTargets()
            if let currentId = injectedPageId {
                let stillExists = targets.contains(where: { $0.id == currentId })
                if !stillExists {
                    // Page reloaded or navigated - reconnect
                    await client?.disconnect()
                    client = nil
                    injectedPageId = nil
                    await injectIntoCodex()
                }
            } else {
                // No current injection - try to find a target
                await injectIntoCodex()
            }
        } catch {
            // Connection issues - will retry
        }
    }

    // MARK: - CDP Target Discovery

    private func queryCDPTargets() async throws -> [CDPTarget] {
        let urls = [
            "http://127.0.0.1:\(debugPort)/json",
            "http://[::1]:\(debugPort)/json",
        ]

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
        let pages = targets.filter { target in
            target.type == "page"
                && target.webSocketDebuggerUrl.map { !$0.isEmpty } ?? false
        }

        // Prefer a page with "codex" in title or URL
        for target in pages {
            let haystack = "\(target.title) \(target.url)".lowercased()
            if haystack.contains("codex") {
                return target
            }
        }

        // Fall back to first page
        return pages.first
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
