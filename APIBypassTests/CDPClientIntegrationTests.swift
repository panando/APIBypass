import XCTest
import CodexRouterCore

/// Integration test against a real Codex/ChatGPT CDP target.
///
/// Skips automatically if the app isn't running with `--remote-debugging-port=9222`.
/// To enable: `open -a ChatGPT --args --remote-debugging-port=9222 --remote-allow-origins=http://127.0.0.1:9222`
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

    /// Verifies the injection script patches `models` (the object array Codex's
    /// model picker reads for metadata) via the patched `Response.prototype.json`.
    ///
    /// `patchModelContainer` is responsible for object arrays (`models`) only.
    /// String arrays (`availableModels`, `available_models`) are handled exclusively
    /// by the Statsig patch to prevent cross-container duplication — the picker
    /// renders from both lists, so patching both makes each custom model appear twice.
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

        // Simulate a fetch response with `models` (object array the picker reads
        // for metadata). The injection script must append custom model objects
        // and unhide existing models that match custom names.
        let probe = try await client.evaluateJavaScript(#"""
        (async function() {
          var response = new Response(JSON.stringify({
            models: [{model: "existing-model", displayName: "Existing", hidden: true}]
          }));
          var data = await response.json();
          return JSON.stringify({
            models: data.models,
            length: data.models.length,
          });
        })()
        """#)

        XCTAssertNotNil(probe.value, "Response.json probe returned nil")
        if let json = probe.value,
           let data = json.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let models = parsed["models"] as? [[String: Any]] ?? []
            let modelNames = models.compactMap { $0["model"] as? String }
            // 1 pre-existing + 2 custom models from the catalog
            XCTAssertGreaterThanOrEqual(models.count, 3,
                                         "models was not patched. Got \(models.count) items: \(modelNames)")
            XCTAssertTrue(modelNames.contains("GPT-5.5"),
                         "models should contain GPT-5.5 from catalog. Got: \(modelNames)")
            XCTAssertTrue(modelNames.contains("Claude Sonnet 4.6"),
                         "models should contain Claude Sonnet 4.6 from catalog. Got: \(modelNames)")
            // Existing model should be unhidden (hidden: false) if it matches a custom name.
            // "existing-model" doesn't match, so it stays hidden: true. We only check that
            // custom models were added with hidden: false.
            let customEntry = models.first(where: { $0["model"] as? String == "GPT-5.5" })
            XCTAssertEqual(customEntry?["hidden"] as? Bool, false,
                           "Custom model should be unhidden (hidden: false). Got: \(customEntry ?? [:])")
        } else {
            XCTFail("Could not parse probe result: \(probe.value ?? "nil")")
        }
    }

    /// Verifies `patchModelContainer` does NOT patch `availableModels` (string array).
    /// String arrays are handled exclusively by the Statsig patch to prevent
    /// cross-container duplication (picker renders from both `models` and
    /// `available_models` — patching both makes each custom model appear twice).
    func test_injectionScript_doesNotPatchAvailableModelsStringArray() async throws {
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

        // Container with ONLY `availableModels` (string array), no `models`.
        // patchModelContainer must NOT touch this — Statsig patch handles it.
        let probe = try await client.evaluateJavaScript(#"""
        (async function() {
          var response = new Response(JSON.stringify({availableModels: ["existing-model"]}));
          var data = await response.json();
          return JSON.stringify({
            availableModels: data.availableModels,
            length: data.availableModels.length,
          });
        })()
        """#)

        XCTAssertNotNil(probe.value, "Response.json probe returned nil")
        if let json = probe.value,
           let data = json.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let available = parsed["availableModels"] as? [String] ?? []
            // Should remain unchanged — patchModelContainer must not patch string arrays.
            XCTAssertEqual(available, ["existing-model"],
                           "availableModels was patched by patchModelContainer (should only be patched by Statsig). Got: \(available)")
        } else {
            XCTFail("Could not parse probe result: \(probe.value ?? "nil")")
        }
    }

    /// Verifies `patchStatsigModelDynamicConfig` only patches the model whitelist
    /// config ("107580212"), not every Statsig dynamic config. Codex registers
    /// multiple dynamic configs whose `value` happens to contain an
    /// `available_models` array; patching all of them causes each custom model
    /// to appear once per config in the picker (×2 duplication).
    ///
    /// Root cause confirmed via diagnostic log: `statsig_config_patched` fired
    /// with two distinct shapes — one with 5 built-ins + 2 custom (the real
    /// whitelist) and one with 0 built-ins + 2 custom (some other config whose
    /// `available_models` was originally empty). The picker merges both → 4
    /// entries for 2 custom models.
    func test_injectionScript_doesNotPatchNonWhitelistStatsigConfigs() async throws {
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
        delete window.__codexPlusModelJsonResponsePatchInstalled;
        delete window.__codexPlusAppServerModelRequestPatchInstalled;
        window.__savedStatsig = window.__STATSIG__;
        window.__STATSIG__ = {
          firstInstance: {
            getDynamicConfig: function(name, options) {
              return { value: { available_models: ["gpt-5"] } };
            }
          }
        };
        """)

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

        var patchInstalled = false
        for _ in 0..<40 {
            let result = try await client.evaluateJavaScript(
                "window.__STATSIG__.firstInstance.__codexPlusModelWhitelistPatched === true"
            )
            if result.value == "true" {
                patchInstalled = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(patchInstalled, "Statsig patch was not installed on mock client")

        let probe = try await client.evaluateJavaScript(#"""
        (function() {
          var result = window.__STATSIG__.firstInstance.getDynamicConfig("other_config", {disableExposureLog: true});
          return JSON.stringify({ available_models: result.value.available_models });
        })()
        """#)

        XCTAssertNotNil(probe.value, "Statsig probe returned nil")
        if let json = probe.value,
           let data = json.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let available = parsed["available_models"] as? [String] ?? []
            XCTAssertEqual(available, ["gpt-5"],
                           "Non-whitelist Statsig config was patched (should only patch config name '107580212'). Got: \(available)")
        } else {
            XCTFail("Could not parse probe result: \(probe.value ?? "nil")")
        }

        _ = try? await client.evaluateJavaScript("window.__STATSIG__ = window.__savedStatsig; delete window.__savedStatsig;")
    }

    /// Companion regression test: when the config name IS "107580212", custom
    /// models must still be appended. Guards against over-filtering.
    /// Verifies `patchStatsigModelDynamicConfig` does NOT append custom models
    /// to the Statsig `available_models` string array. The picker renders
    /// `available_models` as a SEPARATE list from the AppServer `model/list`
    /// response (object array with metadata) — patching both makes each custom
    /// model appear twice: once with metadata (reasoning works) and once as a
    /// bare string (reasoning broken). The AppServer response already carries
    /// custom models with full metadata, so the Statsig patch is redundant.
    ///
    /// RED state: current code appends custom names → `available_models` grows
    /// beyond `["gpt-5"]` → this assertion fails. GREEN: `patchStatsigModelDynamicConfig`
    /// becomes a no-op → `available_models` stays `["gpt-5"]`.
    func test_injectionScript_doesNotPatchStatsigConfig_107580212_availableModels() async throws {
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
        delete window.__codexPlusModelJsonResponsePatchInstalled;
        delete window.__codexPlusAppServerModelRequestPatchInstalled;
        window.__savedStatsig = window.__STATSIG__;
        window.__STATSIG__ = {
          firstInstance: {
            getDynamicConfig: function(name, options) {
              return { value: { available_models: ["gpt-5"] } };
            }
          }
        };
        """)

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

        var patchInstalled = false
        for _ in 0..<40 {
            let result = try await client.evaluateJavaScript(
                "window.__STATSIG__.firstInstance.__codexPlusModelWhitelistPatched === true"
            )
            if result.value == "true" {
                patchInstalled = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(patchInstalled, "Statsig patch was not installed on mock client")

        let probe = try await client.evaluateJavaScript(#"""
        (function() {
          var result = window.__STATSIG__.firstInstance.getDynamicConfig("107580212", {disableExposureLog: true});
          return JSON.stringify({ available_models: result.value.available_models });
        })()
        """#)

        XCTAssertNotNil(probe.value, "Statsig probe returned nil")
        if let json = probe.value,
           let data = json.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let available = parsed["available_models"] as? [String] ?? []
            XCTAssertEqual(available, ["gpt-5"],
                           "Statsig `available_models` must NOT be patched — custom models come from the AppServer response (with metadata). Patching both causes duplication. Got: \(available)")
        } else {
            XCTFail("Could not parse probe result: \(probe.value ?? "nil")")
        }

        _ = try? await client.evaluateJavaScript("window.__STATSIG__ = window.__savedStatsig; delete window.__savedStatsig;")
    }

    /// Verifies `scheduleCodexModelWhitelistRefresh` debounces the refresh tick
    /// aggressively. Before the fix, the tick ran every 120ms for the full
    /// 2500ms refresh window, and the window kept getting extended by every
    /// DOM mutation — so under a mutation burst the tick chain ran indefinitely
    /// at ~8Hz, each tick calling `patchReactModelState` (up to 220 DOM nodes)
    /// and indirectly `patchObjectGraphForModels` (~200 calls/s total).
    /// Diagnostic log showed 7112 `graphPatchCalls` in 35s → renderer saturated
    /// → continuous white screen.
    ///
    /// After the fix, the tick interval is 1000ms and the chain stops when a
    /// pass reports no React state changes. Under a 50-mutation burst over 1s,
    /// refresh pass count over 2s must stay bounded (< 10).
    func test_injectionScript_debouncesModelWhitelistRefresh() async throws {
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
        delete window.__codexPlusModelJsonResponsePatchInstalled;
        delete window.__codexPlusAppServerModelRequestPatchInstalled;
        window.__codexPlusRefreshPassCount = 0;
        """)

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

        // Wait for bootstrap to finish (initial refresh pass + observer start).
        try await Task.sleep(for: .milliseconds(500))
        _ = try await client.evaluateJavaScript("window.__codexPlusRefreshPassCount = 0;")

        // Burst 50 DOM mutations over ~1s — simulates React re-renders triggering
        // the MutationObserver. Before the fix, this would extend the refresh
        // window repeatedly and run ~8 ticks/s.
        for _ in 0..<50 {
            _ = try? await client.evaluateJavaScript("""
            (function(){ var d = document.createElement('div'); d.id = 'mutation-probe'; document.body.appendChild(d); document.body.removeChild(d); })();
            """)
            try await Task.sleep(for: .milliseconds(20))
        }

        // Wait 1s after the burst for any scheduled ticks to fire.
        try await Task.sleep(for: .milliseconds(1000))

        let result = try await client.evaluateJavaScript("String(window.__codexPlusRefreshPassCount || 0)")
        let count = Int(result.value ?? "0") ?? 0

        XCTAssertLessThan(count, 10,
                         "Refresh pass ran \(count) times during a 50-mutation burst — debounce regressed. Before-fix rate was ~16; after-fix should be < 10.")
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

    /// Verifies that the injection script works correctly when `codexAppPluginEntryUnlock`
    /// is absent from settings. This tests forward compatibility after the field is removed.
    func test_bridge_worksWithoutPluginEntryUnlockField() async throws {
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
        """)

        // Settings WITHOUT codexAppPluginEntryUnlock field
        let pushedSettings = """
        {"codexAppForcePluginInstall":true,"enhancementsEnabled":true,"launchMode":"patch","codexAppVersion":"","codexAppPluginMarketplaceUnlock":true,"codexAppModelWhitelistUnlock":true,"modelProvider":"NO_ENTRY_UNLOCK","proxyPort":15721}
        """
        let bridgeSettings = """
        {"codexAppForcePluginInstall":true,"enhancementsEnabled":true,"launchMode":"patch","codexAppVersion":"","codexAppPluginMarketplaceUnlock":true,"codexAppModelWhitelistUnlock":true,"modelProvider":"apibypass","proxyPort":15721}
        """
        let mockCatalog = """
        {"status":"ok","models":[{"model":"test-model","displayName":"Test Model","contextWindow":128000}]}
        """

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

        try await client.addScriptToEvaluateOnNewDocument(cdpBridgeScript)
        _ = try await client.evaluateJavaScript(cdpBridgeScript)

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

        // Evaluate the injection script - should NOT throw
        _ = try await client.evaluateJavaScript(codexPluginInjectionScript)

        // Poll for the bridge to fetch settings
        var modelProvider: String?
        for _ in 0..<30 {
            let result = try await client.evaluateJavaScript(
                "window.__codexPlusBackendSettings && window.__codexPlusBackendSettings.modelProvider"
            )
            if let value = result.value, value != "NO_ENTRY_UNLOCK" && value != "undefined" && value != "null" {
                modelProvider = value
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        // The bridge must have been called
        XCTAssertTrue(bridgeCalls.contains("/settings/get"),
                      "Bridge was not called for /settings/get")
        XCTAssertEqual(modelProvider, "apibypass",
                       "Bridge-fetched settings did not reach the renderer when pluginEntryUnlock was absent")
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
