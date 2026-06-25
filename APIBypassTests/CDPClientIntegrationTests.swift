import XCTest
import CodexRouterCore

/// Integration test against a real Codex CDP target.
///
/// Skips automatically if Codex isn't running with `--remote-debugging-port=9222`.
/// To enable: `open -a Codex --args --remote-debugging-port=9222 --remote-allow-origins=http://127.0.0.1:9222`
///
/// Validates that `CDPClient` (NWConnection-backed) can:
///   1. Complete the WebSocket handshake with Chromium DevTools
///   2. Send `Runtime.enable` and receive its response
///   3. Send `Runtime.evaluate` and receive the evaluated value
///
/// This is the regression guard for the transport layer — `URLSessionWebSocketTask`
/// silently hung against Chromium; if a future refactor reverts to it, this test
/// will hang and fail.
final class CDPClientIntegrationTests: XCTestCase {

    private static func discoverPageWSURL() async throws -> URL? {
        for urlString in CDPProbeURLs(port: 9222) {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                if let targets = try? JSONDecoder().decode([CDPTarget].self, from: data),
                   let page = targets.first(where: { $0.type == "page" }),
                   let ws = page.webSocketDebuggerUrl,
                   let wsURL = URL(string: ws) {
                    return wsURL
                }
            } catch { continue }
        }
        return nil
    }

    func test_connectsAndEvaluatesJavaScript() async throws {
        guard let wsURL = try? await Self.discoverPageWSURL() else {
            throw XCTSkip("Codex not running with --remote-debugging-port=9222; skipping integration test")
        }

        let client = CDPClient(wsURL: wsURL)
        try await client.connect()
        defer { Task { await client.disconnect() } }

        let result = try await client.evaluateJavaScript("1+1")
        XCTAssertEqual(result.value, "2")

        // The injection script sets this global; if it's undefined, injection hasn't run.
        // (This test doesn't trigger injection — it only verifies the transport — so we
        // don't assert the value, just that the call returns without hanging.)
        _ = try await client.evaluateJavaScript("typeof window.__codexPlusBackendSettings")
    }

    /// Verifies the CDP binding bridge path end-to-end:
    ///   1. `addBinding` registers a `Runtime.addBinding` on the renderer
    ///   2. JS calling `window.{name}(payload)` delivers the payload to our handler
    ///   3. The handler's return value reaches JS via `window.__codexSessionDeleteResolve(id, result)`
    ///
    /// This is the tracer bullet for the CSP bypass — if this works, the full bridge
    /// (JS `__codexSessionDeleteBridge` → native HTTP forward → JS promise resolve)
    /// will work, because it's the same mechanism with a thin JS wrapper on top.
    func test_addBinding_routesCallToHandlerAndResolvesBackToJS() async throws {
        guard let wsURL = try? await Self.discoverPageWSURL() else {
            throw XCTSkip("Codex not running with --remote-debugging-port=9222; skipping integration test")
        }

        let client = CDPClient(wsURL: wsURL)
        try await client.connect()
        defer { Task { await client.disconnect() } }

        // Install minimal resolve stub that captures the result into a global.
        // (In production, the full bridge script defines `__codexSessionDeleteBridge`
        // plus resolve/reject; here we only need resolve to verify the round-trip.)
        _ = try await client.evaluateJavaScript("""
        window.__codexSessionDeleteResolve = function(id, result) {
          window.__testBindingResult = String(result);
        };
        window.__testBindingResult = null;
        """)

        let handlerInvoked = expectation(description: "Binding handler invoked")
        let handler: @Sendable (CDPBindingRequest) async throws -> Data = { request in
            XCTAssertEqual(request.path, "/echo")
            handlerInvoked.fulfill()
            let payloadStr = String(data: request.payload ?? Data(), encoding: .utf8) ?? ""
            return "echo:\(payloadStr)".data(using: .utf8)!
        }

        try await client.addBinding(name: "testBinding", handler: handler)

        // Fire the binding from JS. The payload format matches what the production
        // bridge script sends: {id, path, payload}.
        _ = try await client.evaluateJavaScript(#"""
        window.testBinding(JSON.stringify({id: 42, path: "/echo", payload: "hello"}));
        """#)

        await fulfillment(of: [handlerInvoked], timeout: 5.0)

        // After the handler returns, CDPClient evaluates `__codexSessionDeleteResolve(42, "echo:hello")`
        // asynchronously. Poll until the global is set.
        var captured: String?
        for _ in 0..<20 {
            let result = try await client.evaluateJavaScript("window.__testBindingResult")
            if let value = result.value, value != "null" && value != "undefined" {
                captured = value
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(captured, "echo:hello")
    }

    /// Verifies the full bridge + injection script path: bridge is installed,
    /// injection script calls `__codexSessionDeleteBridge` for /settings/get and
    /// /codex-model-catalog, the handler returns mock data, and the settings
    /// are updated in the renderer.
    ///
    /// This is the regression guard for the CSP bypass — if Codex's CSP blocks
    /// localhost fetches and the bridge isn't wired up, neither path is called.
    func test_bridge_withInjectionScript_loadsSettingsAndCatalog() async throws {
        guard let wsURL = try? await Self.discoverPageWSURL() else {
            throw XCTSkip("Codex not running with --remote-debugging-port=9222; skipping integration test")
        }

        let client = CDPClient(wsURL: wsURL)
        try await client.connect()
        defer { Task { await client.disconnect() } }

        // Clean up any bridge globals left by prior tests sharing this page
        // (test_addBinding installs a custom __codexSessionDeleteResolve).
        _ = try? await client.evaluateJavaScript("""
        delete window.__codexSessionDeleteBridge;
        delete window.__codexSessionDeleteResolve;
        delete window.__codexSessionDeleteReject;
        delete window.__codexSessionDeletePending;
        delete window.__codexSessionDeleteIdCounter;
        delete window.__testBindingResult;
        """);

        // Settings pushed via postMessage use a sentinel modelProvider so we can
        // tell them apart from the bridge-fetched settings. If the bridge works,
        // fetchBackendSettings() overwrites this with "apibypass".
        let pushedSettings = """
        {"codexAppPluginEntryUnlock":true,"codexAppForcePluginInstall":true,"enhancementsEnabled":true,"launchMode":"patch","codexAppVersion":"","codexAppPluginMarketplaceUnlock":true,"codexAppModelWhitelistUnlock":true,"modelProvider":"PUSHED","proxyPort":15721}
        """
        let bridgeSettings = """
        {"codexAppPluginEntryUnlock":true,"codexAppForcePluginInstall":true,"enhancementsEnabled":true,"launchMode":"patch","codexAppVersion":"","codexAppPluginMarketplaceUnlock":true,"codexAppModelWhitelistUnlock":true,"modelProvider":"apibypass","proxyPort":15721}
        """
        let mockCatalog = """
        {"status":"ok","models":[{"model":"gpt-5.5","displayName":"GPT-5.5","contextWindow":128000},{"model":"claude-sonnet-4-6","displayName":"Claude Sonnet 4.6","contextWindow":200000}]}
        """

        // Track which paths the bridge was called with.
        let bridgeCalls = BridgeCallLog()
        try await client.addBinding(name: cdpBridgeBindingName) { request in
            bridgeCalls.record(request.path)
            let response: String
            switch request.path {
            case "/settings/get": response = bridgeSettings
            case "/codex-model-catalog": response = mockCatalog
            case "/cdp/diagnostic": response = "{}"
            default: response = "{\"error\":\"unknown\"}"
            }
            return response.data(using: .utf8) ?? Data()
        }

        // Install the bridge script.
        try await client.addScriptToEvaluateOnNewDocument(cdpBridgeScript)
        _ = try await client.evaluateJavaScript(cdpBridgeScript)

        // Push settings via postMessage (like CodexAppInjector.pushSettings does).
        let b64 = pushedSettings.data(using: .utf8)!.base64EncodedString()
        _ = try await client.evaluateJavaScript("""
        (function() {
          try {
            var s = JSON.parse(atob('\(b64)'));
            window.__codexPlusBackendSettings = s;
            window.postMessage({ type: 'codexPlusSettingsUpdate', settings: s }, '*');
          } catch (e) {}
        })();
        """)

        // Evaluate the injection script.
        _ = try await client.evaluateJavaScript(codexPluginInjectionScript)

        // Poll for the bridge to fetch settings (overwriting "PUSHED" with "apibypass").
        var modelProvider: String?
        for _ in 0..<30 {
            let result = try await client.evaluateJavaScript(
                "window.__codexPlusBackendSettings && window.__codexPlusBackendSettings.modelProvider"
            )
            if let value = result.value, value != "PUSHED" && value != "undefined" && value != "null" {
                modelProvider = value
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        // The bridge must have been called for both settings and catalog.
        XCTAssertTrue(bridgeCalls.contains("/settings/get"),
                      "Bridge was not called for /settings/get")
        XCTAssertTrue(bridgeCalls.contains("/codex-model-catalog"),
                      "Bridge was not called for /codex-model-catalog")

        // The bridge-fetched settings must have overwritten the pushed sentinel.
        XCTAssertEqual(modelProvider, "apibypass",
                       "Bridge-fetched settings did not reach the renderer")
    }

    /// Verifies the injection script populates an EMPTY model container via the
    /// patched `Response.prototype.json`.
    ///
    /// This is the tracer for the "Codex not logged in → empty model list" bug:
    /// when Codex's model picker has `{models: []}` with no `defaultModel` or
    /// `availableModels` field, the injection script's `patchModelArray` currently
    /// skips the empty array (because `allowEmpty` is false). The fix is to
    /// populate empty arrays from the catalog.
    func test_injectionScript_populatesEmptyModelContainer() async throws {
        guard let wsURL = try? await Self.discoverPageWSURL() else {
            throw XCTSkip("Codex not running with --remote-debugging-port=9222; skipping integration test")
        }

        let client = CDPClient(wsURL: wsURL)
        try await client.connect()
        defer { Task { await client.disconnect() } }

        // Clean up globals from prior tests sharing this page
        _ = try? await client.evaluateJavaScript("""
        delete window.__codexSessionDeleteBridge;
        delete window.__codexSessionDeleteResolve;
        delete window.__codexSessionDeleteReject;
        delete window.__codexSessionDeletePending;
        delete window.__codexSessionDeleteIdCounter;
        delete window.__codexPlusBackendSettings;
        delete window.__codexPlusModelJsonResponsePatchInstalled;
        delete window.__codexPlusAppServerModelRequestPatchInstalled;
        """);

        let bridgeSettings = """
        {"codexAppPluginEntryUnlock":true,"codexAppForcePluginInstall":true,"enhancementsEnabled":true,"launchMode":"patch","codexAppVersion":"","codexAppPluginMarketplaceUnlock":true,"codexAppModelWhitelistUnlock":true,"modelProvider":"apibypass","proxyPort":15721}
        """
        let mockCatalog = """
        {"status":"ok","models":[{"model":"gpt-5.5","displayName":"GPT-5.5","contextWindow":128000},{"model":"claude-sonnet-4-6","displayName":"Claude Sonnet 4.6","contextWindow":200000}]}
        """

        try await client.addBinding(name: cdpBridgeBindingName) { request in
            let response: String
            switch request.path {
            case "/settings/get": response = bridgeSettings
            case "/codex-model-catalog": response = mockCatalog
            case "/cdp/diagnostic": response = "{}"
            default: response = "{\"error\":\"unknown\"}"
            }
            return response.data(using: .utf8) ?? Data()
        }

        try await client.addScriptToEvaluateOnNewDocument(cdpBridgeScript)
        _ = try await client.evaluateJavaScript(cdpBridgeScript)
        _ = try await client.evaluateJavaScript(codexPluginInjectionScript)

        // Wait for the Response.json patch to be installed (happens after catalog loads).
        var patchInstalled = false
        for _ in 0..<40 {
            let result = try await client.evaluateJavaScript(
                "window.__codexPlusModelJsonResponsePatchInstalled === '1'"
            )
            if result.value == "true" {
                patchInstalled = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(patchInstalled,
                      "Response.json patch was not installed. Check that catalog loaded and shouldPatchModels() is true.")

        // Simulate a fetch response with an EMPTY models container — the exact
        // shape Codex's model picker would have when not logged in.
        // No `defaultModel` or `availableModels` field, so allowEmpty is false
        // under the current logic.
        let probe = try await client.evaluateJavaScript(#"""
        (async function() {
          var response = new Response(JSON.stringify({models: []}));
          var data = await response.json();
          return JSON.stringify({
            modelsLength: (data.models || []).length,
            firstModel: data.models && data.models[0] ? data.models[0].model : null,
          });
        })()
        """#)

        XCTAssertNotNil(probe.value, "Response.json probe returned nil")
        // The empty models array must have been populated from the catalog.
        if let json = probe.value,
           let data = json.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let modelsLength = parsed["modelsLength"] as? Int ?? 0
            let firstModel = parsed["firstModel"] as? String
            XCTAssertGreaterThan(modelsLength, 0,
                                 "Empty model container was not populated. models still empty.")
            XCTAssertEqual(firstModel, "GPT-5.5",
                           "First model should be from the catalog (displayName is used as model slug). Got: \(firstModel ?? "nil")")
        } else {
            XCTFail("Could not parse probe result: \(probe.value ?? "nil")")
        }
    }

    /// Verifies the injection script's scan loop is NOT a tight requestAnimationFrame
    /// loop (60fps). A tight loop runs `scanDeferred` ~90 times in 1.5s, which
    /// combined with `spoofChatGPTAuthMethod`'s React fiber traversal causes Codex
    /// to freeze on startup when `pluginEntryUnlock` is enabled.
    ///
    /// The fix follows CodexPlusPlus's pattern: MutationObserver + 200ms debounce,
    /// which yields ~5-8 scans in 1.5s. We assert < 20 to allow for the initial
    /// scan burst plus MutationObserver triggers, while still catching a regression
    /// to the tight rAF loop (~90).
    func test_injectionScript_doesNotScanInTightLoop() async throws {
        guard let wsURL = try? await Self.discoverPageWSURL() else {
            throw XCTSkip("Codex not running with --remote-debugging-port=9222; skipping integration test")
        }

        let client = CDPClient(wsURL: wsURL)
        try await client.connect()
        defer { Task { await client.disconnect() } }

        // Clean up globals from prior tests
        _ = try? await client.evaluateJavaScript("""
        delete window.__codexSessionDeleteBridge;
        delete window.__codexSessionDeleteResolve;
        delete window.__codexSessionDeleteReject;
        delete window.__codexSessionDeletePending;
        delete window.__codexSessionDeleteIdCounter;
        delete window.__codexPlusBackendSettings;
        delete window.__codexPlusScanCount;
        """)

        let bridgeSettings = """
        {"codexAppPluginEntryUnlock":true,"codexAppForcePluginInstall":true,"enhancementsEnabled":true,"launchMode":"patch","codexAppVersion":"","codexAppPluginMarketplaceUnlock":true,"codexAppModelWhitelistUnlock":true,"modelProvider":"apibypass","proxyPort":15721}
        """
        let mockCatalog = """
        {"status":"ok","models":[{"model":"gpt-5.5","displayName":"GPT-5.5","contextWindow":128000}]}
        """

        try await client.addBinding(name: cdpBridgeBindingName) { request in
            let response: String
            switch request.path {
            case "/settings/get": response = bridgeSettings
            case "/codex-model-catalog": response = mockCatalog
            case "/cdp/diagnostic": response = "{}"
            default: response = "{\"error\":\"unknown\"}"
            }
            return response.data(using: .utf8) ?? Data()
        }

        try await client.addScriptToEvaluateOnNewDocument(cdpBridgeScript)
        _ = try await client.evaluateJavaScript(cdpBridgeScript)
        _ = try await client.evaluateJavaScript(codexPluginInjectionScript)

        // Reset counter after injection (bootstrap's initial scan runs immediately).
        _ = try await client.evaluateJavaScript("window.__codexPlusScanCount = 0;")

        // Wait 1.5 seconds — a tight rAF loop would run ~90 scans; a debounced
        // MutationObserver would run 0-5 unless DOM is changing.
        try await Task.sleep(for: .milliseconds(1500))

        let result = try await client.evaluateJavaScript("String(window.__codexPlusScanCount || 0)")
        let count = Int(result.value ?? "0") ?? 0

        XCTAssertLessThan(count, 20,
                         "Scan loop ran \(count) times in 1.5s — tight rAF loop not replaced. Expected < 20 with MutationObserver + debounce.")
    }

    /// Verifies the scan loop does NOT fire for DOM mutations that are irrelevant
    /// to Codex's scan-relevant selectors (sidebar threads, chat content, install
    /// buttons, etc.).
    ///
    /// This is the tracer bullet for the `pluginEntryUnlock` freeze fix. The freeze
    /// is caused by a feedback loop: `enablePluginEntry` calls `spoofChatGPTAuthMethod`
    /// → React re-render → DOM mutation → unfiltered MutationObserver fires → scan
    /// → `enablePluginEntry` again. Porting CPP's `shouldScheduleScan(mutations)`
    /// filter breaks the loop by ignoring mutations that aren't scan-relevant.
    ///
    /// A plain `<div>` appended to body is not scan-relevant, so scan count must
    /// stay at 0. If the filter is missing or broken, the count is 1.
    func test_injectionScript_doesNotScanForIrrelevantMutations() async throws {
        guard let wsURL = try? await Self.discoverPageWSURL() else {
            throw XCTSkip("Codex not running with --remote-debugging-port=9222; skipping integration test")
        }

        let client = CDPClient(wsURL: wsURL)
        try await client.connect()
        defer { Task { await client.disconnect() } }

        _ = try? await client.evaluateJavaScript("""
        delete window.__codexSessionDeleteBridge;
        delete window.__codexSessionDeleteResolve;
        delete window.__codexSessionDeleteReject;
        delete window.__codexSessionDeletePending;
        delete window.__codexSessionDeleteIdCounter;
        delete window.__codexPlusBackendSettings;
        delete window.__codexPlusScanCount;
        """)

        let bridgeSettings = """
        {"codexAppPluginEntryUnlock":true,"codexAppForcePluginInstall":true,"enhancementsEnabled":true,"launchMode":"patch","codexAppVersion":"","codexAppPluginMarketplaceUnlock":true,"codexAppModelWhitelistUnlock":true,"modelProvider":"apibypass","proxyPort":15721}
        """
        let mockCatalog = """
        {"status":"ok","models":[{"model":"gpt-5.5","displayName":"GPT-5.5","contextWindow":128000}]}
        """

        try await client.addBinding(name: cdpBridgeBindingName) { request in
            let response: String
            switch request.path {
            case "/settings/get": response = bridgeSettings
            case "/codex-model-catalog": response = mockCatalog
            case "/cdp/diagnostic": response = "{}"
            default: response = "{\"error\":\"unknown\"}"
            }
            return response.data(using: .utf8) ?? Data()
        }

        try await client.addScriptToEvaluateOnNewDocument(cdpBridgeScript)
        _ = try await client.evaluateJavaScript(cdpBridgeScript)
        _ = try await client.evaluateJavaScript(codexPluginInjectionScript)

        // Wait for bootstrap's fetchBackendSettings to complete — this is the
        // reliable signal that bootstrap has progressed past its await. Once
        // modelProvider is "apibypass", the bridge call has resolved and scan()
        // will run in the same microtask.
        var bootstrapped = false
        for _ in 0..<50 {
            let result = try await client.evaluateJavaScript(
                "window.__codexPlusBackendSettings && window.__codexPlusBackendSettings.modelProvider === 'apibypass'"
            )
            if result.value == "true" {
                bootstrapped = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(bootstrapped, "Bootstrap never completed — fetchBackendSettings did not resolve")

        // Give bootstrap's scan() one rAF to fire and increment the counter.
        try await Task.sleep(for: .milliseconds(200))

        // Reset counter after bootstrap.
        _ = try await client.evaluateJavaScript("window.__codexPlusScanCount = 0;")

        // Append an irrelevant DOM node — not a sidebar thread, chat content,
        // install button, or any scan-relevant selector.
        _ = try await client.evaluateJavaScript("""
        var probe = document.createElement('div');
        probe.id = 'codex-plus-probe-irrelevant';
        probe.textContent = 'irrelevant';
        document.body.appendChild(probe);
        """)

        // Wait long enough for the 200ms debounce to fire if the scan was scheduled.
        try await Task.sleep(for: .milliseconds(500))

        let result = try await client.evaluateJavaScript("String(window.__codexPlusScanCount || 0)")
        let count = Int(result.value ?? "-1") ?? -1

        XCTAssertEqual(count, 0,
                       "Irrelevant DOM mutation triggered a scan (count=\(count)). shouldScheduleScan filter is missing or broken — this is the feedback loop that freezes Codex on startup when pluginEntryUnlock is enabled.")
    }
}

/// Thread-safe log of bridge call paths, used by the integration test to verify
/// the injection script actually invoked `__codexSessionDeleteBridge`.
private final class BridgeCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    func record(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        paths.append(path)
    }

    func contains(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return paths.contains(path)
    }
}
