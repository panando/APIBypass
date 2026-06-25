# CDP Injection Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make CDP injection observable — injection script reports patch install/failure events via HTTP to APIBypass log, and CDP connection state is surfaced in the UI.

**Architecture:** HTTP push diagnostics channel (ported from Codex Plus Plus's `sendCodexPlusDiagnostic`) sends events to a new `POST /cdp/diagnostic` endpoint, which writes to the existing `CodexLogStore`. Separately, `CodexAppInjector` exposes a `CDPConnectionState` enum that `CodexAdaptorService` polls and the UI displays as a status indicator. Port is dynamically passed to the injection script via `CDPInjectionSettings.proxyPort` (pushed via CDP before script injection), eliminating hardcoded `15721`.

**Tech Stack:** Swift, Hummingbird, XCTest, JavaScript (injected via CDP).

---

## File Structure

- **Modify:** `CodexRouterCore/CDP/CDPTypes.swift` — add `proxyPort` field to `CDPInjectionSettings`; add `CDPConnectionState` enum
- **Modify:** `CodexRouterCore/CDP/CodexAppInjector.swift` — add `connectionState` + `snapshotState()`; log all catch blocks; state transitions
- **Modify:** `CodexRouterCore/CDP/CDPInjectionScript.swift` — add `sendCodexPlusDiagnostic` + `codexPlusBackendBase()`; replace hardcoded port; add diagnostic calls in all catch blocks + event points
- **Modify:** `APIBypass/Core/CodexRouter/CodexRoutes.swift` — add `POST /cdp/diagnostic` route
- **Modify:** `APIBypass/Core/CodexRouter/CodexRequestHandler.swift` — add `formatDiagnosticLogLine` + `diagnosticLogLevel` pure functions
- **Modify:** `APIBypass/Core/CodexAdaptorService.swift` — populate `proxyPort` in `handleSettingsGet`; add `cdpConnectionState` + polling
- **Modify:** `APIBypass/UI/Views/CodexAdaptorView.swift` — add CDP status indicator in enhancements card
- **Modify:** `APIBypass/Core/LocalizationManager.swift` — add `cdp_status_*` keys
- **Create:** `APIBypassTests/CDPDiagnosticsTests.swift` — pure function unit tests

---

## Task 1: Add `proxyPort` to `CDPInjectionSettings`

**Files:**
- Modify: `CodexRouterCore/CDP/CDPTypes.swift`

- [ ] **Step 1: Add the field**

In `CodexRouterCore/CDP/CDPTypes.swift`, replace the `CDPInjectionSettings` struct with:

```swift
/// CDP settings exposed to injected JavaScript via /settings/get endpoint.
public struct CDPInjectionSettings: Codable, Sendable, Equatable {
    public var codexAppPluginEntryUnlock: Bool
    public var codexAppForcePluginInstall: Bool
    public var enhancementsEnabled: Bool
    public var launchMode: String
    public var codexAppVersion: String
    public var codexAppPluginMarketplaceUnlock: Bool
    public var codexAppModelWhitelistUnlock: Bool
    public var modelProvider: String
    public var proxyPort: Int

    public init(
        codexAppPluginEntryUnlock: Bool = true,
        codexAppForcePluginInstall: Bool = true,
        enhancementsEnabled: Bool = true,
        launchMode: String = "patch",
        codexAppVersion: String = "",
        codexAppPluginMarketplaceUnlock: Bool = true,
        codexAppModelWhitelistUnlock: Bool = true,
        modelProvider: String = "",
        proxyPort: Int = 15721
    ) {
        self.codexAppPluginEntryUnlock = codexAppPluginEntryUnlock
        self.codexAppForcePluginInstall = codexAppForcePluginInstall
        self.enhancementsEnabled = enhancementsEnabled
        self.launchMode = launchMode
        self.codexAppVersion = codexAppVersion
        self.codexAppPluginMarketplaceUnlock = codexAppPluginMarketplaceUnlock
        self.codexAppModelWhitelistUnlock = codexAppModelWhitelistUnlock
        self.modelProvider = modelProvider
        self.proxyPort = proxyPort
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift build 2>&1 | tail -5`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/panando/ClaudeCode/APIbypass
git add CodexRouterCore/CDP/CDPTypes.swift
git commit -m "feat(cdp): add proxyPort to CDPInjectionSettings"
```

---

## Task 2: Populate `proxyPort` in settings handler

**Files:**
- Modify: `APIBypass/Core/CodexAdaptorService.swift`

- [ ] **Step 1: Populate the field**

In `APIBypass/Core/CodexAdaptorService.swift`, find the `handleSettingsGet()` method and replace it with:

```swift
    func handleSettingsGet() async -> (Int, String, String) {
        var settings = await currentInjectionSettings()
        settings.modelProvider = (try? CodexConfigService.shared.getCurrentUpstreamProvider()?.id) ?? ""
        settings.proxyPort = port
        let jsonData = (try? JSONEncoder().encode(settings)) ?? Data()
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            return (500, "application/json", #"{"error":"encode failed"}"#)
        }
        return (200, "application/json", jsonString)
    }
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift build 2>&1 | tail -5`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/panando/ClaudeCode/APIbypass
git add APIBypass/Core/CodexAdaptorService.swift
git commit -m "feat(codex): populate proxyPort in /settings/get response"
```

---

## Task 3: Add pure functions `formatDiagnosticLogLine` + `diagnosticLogLevel` with TDD

**Files:**
- Create: `APIBypassTests/CDPDiagnosticsTests.swift`
- Modify: `APIBypass/Core/CodexRouter/CodexRequestHandler.swift`

- [ ] **Step 1: Write the failing tests**

Create `APIBypassTests/CDPDiagnosticsTests.swift`:

```swift
import XCTest
@testable import APIBypass

final class CDPDiagnosticsTests: XCTestCase {

    // MARK: - formatDiagnosticLogLine

    func test_formatDiagnosticLogLine_basicEventWithDetail() {
        let line = CodexRequestHandler.formatDiagnosticLogLine(
            event: "statsig_patch_installed",
            detail: ["clientCount": 1]
        )
        XCTAssertEqual(line, #"[CDP] statsig_patch_installed {"clientCount":1}"#)
    }

    func test_formatDiagnosticLogLine_emptyDetail() {
        let line = CodexRequestHandler.formatDiagnosticLogLine(
            event: "script_loaded",
            detail: [:]
        )
        XCTAssertEqual(line, #"[CDP] script_loaded {}"#)
    }

    func test_formatDiagnosticLogLine_multipleDetailKeys() {
        let line = CodexRequestHandler.formatDiagnosticLogLine(
            event: "appserver_request_patch_not_found",
            detail: ["exportCount": 0, "candidateCount": 0]
        )
        // JSONSerialization sorts keys alphabetically
        XCTAssertEqual(line, #"[CDP] appserver_request_patch_not_found {"candidateCount":0,"exportCount":0}"#)
    }

    func test_formatDiagnosticLogLine_stringDetailValue() {
        let line = CodexRequestHandler.formatDiagnosticLogLine(
            event: "catalog_failed",
            detail: ["error": "network timeout"]
        )
        XCTAssertEqual(line, #"[CDP] catalog_failed {"error":"network timeout"}"#)
    }

    // MARK: - diagnosticLogLevel

    func test_diagnosticLogLevel_failedSuffix_returnsError() {
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "catalog_failed"), .error)
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "statsig_patch_failed"), .error)
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "appserver_request_patch_failed"), .error)
    }

    func test_diagnosticLogLevel_notFoundSuffix_returnsInfo() {
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "appserver_request_patch_not_found"), .info)
    }

    func test_diagnosticLogLevel_installedSuffix_returnsInfo() {
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "statsig_patch_installed"), .info)
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "script_loaded"), .info)
        XCTAssertEqual(CodexRequestHandler.diagnosticLogLevel(for: "model_whitelist_refresh_scheduled"), .info)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift test --filter CDPDiagnosticsTests 2>&1 | tail -20`
Expected: compile error — `formatDiagnosticLogLine` and `diagnosticLogLevel` do not exist.

- [ ] **Step 3: Add the pure functions**

In `APIBypass/Core/CodexRouter/CodexRequestHandler.swift`, add immediately below the `makeModelCatalogBody` function (around line 66):

```swift
    /// Format a diagnostic event as a log line: `[CDP] {event} {detailJSON}`.
    /// Pure function — safe to unit-test.
    static func formatDiagnosticLogLine(event: String, detail: [String: Any]) -> String {
        let jsonData = (try? JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys])) ?? Data()
        let detailJSON = String(data: jsonData, encoding: .utf8) ?? "{}"
        return "[CDP] \(event) \(detailJSON)"
    }

    /// Map a diagnostic event name to a log level.
    /// - `*_failed` → `.error`
    /// - `*_not_found` → `.info` (webpack module not yet loaded is normal)
    /// - otherwise → `.info`
    /// Pure function — safe to unit-test.
    static func diagnosticLogLevel(for event: String) -> DisplayLogLevel {
        if event.hasSuffix("_failed") {
            return .error
        }
        return .info
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift test --filter CDPDiagnosticsTests 2>&1 | tail -15`
Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/panando/ClaudeCode/APIbypass
git add APIBypassTests/CDPDiagnosticsTests.swift APIBypass/Core/CodexRouter/CodexRequestHandler.swift
git commit -m "feat(cdp): add formatDiagnosticLogLine and diagnosticLogLevel pure functions"
```

---

## Task 4: Add `POST /cdp/diagnostic` route

**Files:**
- Modify: `APIBypass/Core/CodexRouter/CodexRoutes.swift`

- [ ] **Step 1: Add the route**

In `APIBypass/Core/CodexRouter/CodexRoutes.swift`, add immediately after the `/codex-model-catalog` route (after the closing brace of that route's closure):

```swift
        router.post("/cdp/diagnostic") { request, context in
            let body = try await request.body.collapsed()
            let json = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            let event = (json["event"] as? String) ?? "unknown"
            let detail = (json["detail"] as? [String: Any]) ?? [:]
            let line = CodexRequestHandler.formatDiagnosticLogLine(event: event, detail: detail)
            let level = CodexRequestHandler.diagnosticLogLevel(for: event)
            CodexLogStore.shared.append(level: level, message: line)
            return Response(
                status: .ok,
                body: .init(byteBuffer: ByteBuffer(string: #"{"ok":true}"#))
            )
        }
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift build 2>&1 | tail -5`
Expected: build succeeds. If `request.body.collapsed()` is not the correct API, check how other POST routes in the same file read the body — the `/v1/chat/completions` route reads `request.body` via `CodexRequestHandler.handle`, which internally uses `try await request.body.collapsed()` or similar. Match the existing pattern.

- [ ] **Step 3: Commit**

```bash
cd /Users/panando/ClaudeCode/APIbypass
git add APIBypass/Core/CodexRouter/CodexRoutes.swift
git commit -m "feat(cdp): add POST /cdp/diagnostic route for injection diagnostics"
```

---

## Task 5: Add `CDPConnectionState` enum with localizedName + indicatorColor (TDD)

**Files:**
- Modify: `CodexRouterCore/CDP/CDPTypes.swift`
- Create: `APIBypassTests/CDPConnectionStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `APIBypassTests/CDPConnectionStateTests.swift`:

```swift
import XCTest
import CodexRouterCore
@testable import APIBypass

final class CDPConnectionStateTests: XCTestCase {

    func test_localizedName_disconnected() {
        XCTAssertEqual(CDPConnectionState.disconnected.localizedName, "CDP: 未连接")
    }

    func test_localizedName_connecting() {
        XCTAssertEqual(CDPConnectionState.connecting.localizedName, "CDP: 连接中")
    }

    func test_localizedName_connected() {
        XCTAssertEqual(CDPConnectionState.connected.localizedName, "CDP: 连接中")
    }

    func test_localizedName_injected() {
        XCTAssertEqual(CDPConnectionState.injected.localizedName, "CDP: 已注入")
    }

    func test_localizedName_failed_includesReason() {
        let state = CDPConnectionState.failed("WebSocket timeout")
        XCTAssertEqual(state.localizedName, "CDP: 失败 — WebSocket timeout")
    }
}
```

Note: These tests assert Chinese strings directly because `localizedName` is a pure function returning a fixed string per case (no localization lookup — the spec says "支持本地化" but for this iteration we return Chinese directly to keep the function pure and testable without mocking `LocalizationManager`). If the team later wants English variants, `localizedName` can delegate to `LocalizationManager` and the tests updated.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift test --filter CDPConnectionStateTests 2>&1 | tail -15`
Expected: compile error — `CDPConnectionState` does not exist.

- [ ] **Step 3: Add the enum**

In `CodexRouterCore/CDP/CDPTypes.swift`, add at the end of the file (after the `CDPInjectionSettings` struct):

```swift
/// CDP connection state for UI display.
public enum CDPConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case injected
    case failed(String)

    /// Human-readable label for UI display.
    public var localizedName: String {
        switch self {
        case .disconnected: return "CDP: 未连接"
        case .connecting: return "CDP: 连接中"
        case .connected: return "CDP: 连接中"
        case .injected: return "CDP: 已注入"
        case .failed(let reason): return "CDP: 失败 — \(reason)"
        }
    }
}
```

Note: `indicatorColor` requires `SwiftUI.Color`, but `CDPTypes.swift` is in the `CodexRouterCore` SPM module which does not import SwiftUI. Adding SwiftUI to the SPM module is out of scope. Instead, the color mapping will live in the UI layer (`CodexAdaptorView.swift`) as a computed property on a small extension or a switch statement. This keeps the enum pure and testable without SwiftUI dependencies.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift test --filter CDPConnectionStateTests 2>&1 | tail -15`
Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/panando/ClaudeCode/APIbypass
git add CodexRouterCore/CDP/CDPTypes.swift APIBypassTests/CDPConnectionStateTests.swift
git commit -m "feat(cdp): add CDPConnectionState enum with localizedName"
```

---

## Task 6: Add `connectionState` + `snapshotState()` + `CDPLogger` to `CodexAppInjector`

> **Architectural note:** `CodexAppInjector` is in the `CodexRouterCore` SPM module, which cannot import the app target where `CodexLogStore` lives. We introduce a `CDPLogger` protocol in core that the app layer conforms to. `CodexLogStore` conformance + passing the logger instance happens in Task 7.

**Files:**
- Modify: `CodexRouterCore/CDP/CDPTypes.swift` — add `CDPLogger` protocol
- Modify: `CodexRouterCore/CDP/CodexAppInjector.swift` — add `connectionState` + `snapshotState()` + `logger` field; log via `logger?.logInfo/logError`

- [ ] **Step 1: Add `CDPLogger` protocol to `CDPTypes.swift`**

In `CodexRouterCore/CDP/CDPTypes.swift`, add at the end of the file (after `CDPConnectionState`):

```swift
/// Logging interface for CDP internals, decoupling `CodexRouterCore` from the app's `CodexLogStore`.
public protocol CDPLogger: Sendable {
    func logInfo(_ message: String)
    func logError(_ message: String)
}
```

- [ ] **Step 2: Add `logger` field + `connectionState` property + `snapshotState()` to `CodexAppInjector`**

In `CodexRouterCore/CDP/CodexAppInjector.swift`, add `logger` field and `connectionState` below `private var injectedPageId: String?`:

```swift
    private let logger: CDPLogger?
    private var connectionState: CDPConnectionState = .disconnected
```

Update `init` to accept `logger`:

```swift
    public init(debugPort: UInt16 = 9222, settings: CDPInjectionSettings = CDPInjectionSettings(), logger: CDPLogger? = nil) {
        self.debugPort = debugPort
        self.settings = settings
        self.logger = logger
    }
```

Add a public snapshot method below `stop()`:

```swift
    /// Snapshot current connection state for UI polling.
    public func snapshotState() -> CDPConnectionState {
        return connectionState
    }
```

- [ ] **Step 3: Add state transitions + logging in `injectIntoCodex`**

Replace the entire `injectIntoCodex()` method with:

```swift
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

            let cdpClient = CDPClient(wsURL: wsURL)
            try await cdpClient.connect()
            self.client = cdpClient
            self.injectedPageId = target.id
            connectionState = .connected
            logger?.logInfo("[CDP] WebSocket connected")

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
```

- [ ] **Step 4: Add state transition in `monitorAndReinject`**

Replace the entire `monitorAndReinject()` method with:

```swift
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
            logger?.logError("[CDP] Monitor error: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 5: Add state transition in `stop`**

Replace the `stop()` method with:

```swift
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
```

- [ ] **Step 6: Build to verify**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift build 2>&1 | tail -5`
Expected: build succeeds.

- [ ] **Step 7: Run full test suite to verify no regressions**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift test 2>&1 | tail -10`
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
cd /Users/panando/ClaudeCode/APIbypass
git add CodexRouterCore/CDP/CDPTypes.swift CodexRouterCore/CDP/CodexAppInjector.swift
git commit -m "feat(cdp): add connectionState + snapshotState + CDPLogger to CodexAppInjector"
```

---

## Task 7: Poll `connectionState` in `CodexAdaptorService` + wire `CDPLogger`

**Files:**
- Modify: `APIBypass/Core/CodexRouter/CodexLogStore.swift` — conform to `CDPLogger`
- Modify: `APIBypass/Core/CodexAdaptorService.swift` — add `@Published cdpConnectionState`; pass logger to injector; add polling

- [ ] **Step 1: Conform `CodexLogStore` to `CDPLogger`**

In `APIBypass/Core/CodexRouter/CodexLogStore.swift`, add at the end of the file:

```swift
extension CodexLogStore: CDPLogger {
    func logInfo(_ message: String) { info(message) }
    func logError(_ message: String) { append(level: .error, message: message) }
}
```

- [ ] **Step 2: Add published property**

In `APIBypass/Core/CodexAdaptorService.swift`, add below `@Published var port: Int = 15721`:

```swift
    @Published var cdpConnectionState: CDPConnectionState = .disconnected
```

- [ ] **Step 3: Pass logger + start polling in `start()`**

In the `start()` method, pass `CodexLogStore.shared` as the logger and call `startCDPStatePolling()`:

```swift
        if config.cdpSettings.enhancementsEnabled {
            let inj = CodexAppInjector(
                debugPort: config.cdpDebugPort,
                settings: config.cdpSettings,
                logger: CodexLogStore.shared
            )
            self.injector = inj
            await inj.start()
            startCDPStatePolling()
        }
```

Add the polling method below `start()`:

```swift
    /// Poll CDP connection state from the injector actor every 3 seconds.
    private func startCDPStatePolling() {
        Task { [weak self] in
            while self?.isRunning == true {
                if let inj = await self?.injector {
                    let state = await inj.snapshotState()
                    await MainActor.run {
                        self?.cdpConnectionState = state
                    }
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
```

- [ ] **Step 4: Clear state on stop**

In the `stop()` method, add after `injector = nil`:

```swift
        cdpConnectionState = .disconnected
```

- [ ] **Step 5: Build to verify**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift build 2>&1 | tail -5`
Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
cd /Users/panando/ClaudeCode/APIbypass
git add APIBypass/Core/CodexRouter/CodexLogStore.swift APIBypass/Core/CodexAdaptorService.swift
git commit -m "feat(codex): wire CDPLogger + poll CDP connection state in CodexAdaptorService"
```

---

## Task 8: Add `sendCodexPlusDiagnostic` + `codexPlusBackendBase` to injection script

**Files:**
- Modify: `CodexRouterCore/CDP/CDPInjectionScript.swift`

- [ ] **Step 1: Add the diagnostic helpers**

In `CodexRouterCore/CDP/CDPInjectionScript.swift`, find the line `window.__codexPlusBackendSettings = codexPlusBackendSettings;` in the Bootstrap section (around line 617). Add immediately BEFORE it:

```js
  // ── Diagnostics (ported from Codex Plus Plus) ────────────────────
  function codexPlusBackendBase() {
    const port = codexPlusBackendSettings.proxyPort || 15721;
    return "http://127.0.0.1:" + port;
  }

  function sendCodexPlusDiagnostic(event, detail) {
    try {
      const payload = {
        event: event,
        detail: detail || {},
        location: window.location?.href || "",
        userAgent: navigator.userAgent || "",
        timestamp: new Date().toISOString(),
      };
      fetch(codexPlusBackendBase() + "/cdp/diagnostic", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        keepalive: true,
      }).catch(() => {});
    } catch (_) {}
  }

  sendCodexPlusDiagnostic("script_loaded", { version: "apibypass-1" });
```

- [ ] **Step 2: Replace hardcoded port in `fetchBackendSettings`**

Find the `fetchBackendSettings` function (around line 405). Replace the `fetch("http://127.0.0.1:15721/settings/get")` line with:

```js
        const resp = await fetch(codexPlusBackendBase() + "/settings/get");
```

- [ ] **Step 3: Replace hardcoded port in `loadCodexModelCatalog`**

Find the `loadCodexModelCatalog` function. Replace the `fetch("http://127.0.0.1:15721/codex-model-catalog")` line with:

```js
    codexModelCatalogPromise = fetch(codexPlusBackendBase() + "/codex-model-catalog")
```

- [ ] **Step 4: Add `settings_loaded` diagnostic**

In `fetchBackendSettings`, after `codexPlusBackendSettingsLoaded = true;` (around line 410), add:

```js
        sendCodexPlusDiagnostic("settings_loaded", {
          modelProvider: data.modelProvider || "",
          enhancementsEnabled: data.enhancementsEnabled,
        });
```

- [ ] **Step 5: Build to verify**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift build 2>&1 | tail -5`
Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
cd /Users/panando/ClaudeCode/APIbypass
git add CodexRouterCore/CDP/CDPInjectionScript.swift
git commit -m "feat(cdp): add sendCodexPlusDiagnostic + dynamic port base URL"
```

---

## Task 9: Add diagnostic events to model whitelist patches

**Files:**
- Modify: `CodexRouterCore/CDP/CDPInjectionScript.swift`

- [ ] **Step 1: Add diagnostics to `loadCodexModelCatalog`**

Find the `loadCodexModelCatalog` function. In the `.then((result) => {...})` block, after `codexModelCatalogLoadedAt = Date.now();`, add:

```js
        sendCodexPlusDiagnostic("catalog_loaded", {
          modelCount: Array.isArray(codexModelCatalog.models) ? codexModelCatalog.models.length : 0,
        });
```

In the `.catch(() => {...})` block, after `codexModelCatalogLoadedAt = Date.now();`, add:

```js
        sendCodexPlusDiagnostic("catalog_failed", { error: "fetch failed" });
```

- [ ] **Step 2: Add diagnostics to `patchStatsigModelWhitelist`**

Find `patchStatsigModelWhitelist`. Replace the entire function body (inside the `try { ... } catch (_) {}`) with:

```js
    if (!shouldPatchModels()) return;
    try {
      let clientCount = 0;
      statsigClients().forEach((client) => {
        if (typeof client.getDynamicConfig !== "function") return;
        clientCount += 1;
        if (!client.__codexPlusModelWhitelistPatched) {
          const originalGetDynamicConfig = client.getDynamicConfig.bind(client);
          client.getDynamicConfig = (name, options) => {
            const result = originalGetDynamicConfig(name, options);
            return patchStatsigModelDynamicConfig(result);
          };
          client.__codexPlusModelWhitelistPatched = true;
        }
        try {
          patchStatsigModelDynamicConfig(client.getDynamicConfig("107580212", { disableExposureLog: true }));
        } catch (_) {}
      });
      if (clientCount > 0) {
        sendCodexPlusDiagnostic("statsig_patch_installed", { clientCount: clientCount });
      }
    } catch (e) {
      sendCodexPlusDiagnostic("statsig_patch_failed", { error: String(e?.stack || e) });
    }
```

- [ ] **Step 3: Add diagnostics to `patchAppServerModelMessages`**

Find `patchAppServerModelMessages`. After `window.__codexPlusModelMessagePatchInstalled = true;`, add:

```js
    sendCodexPlusDiagnostic("appserver_message_patch_installed", {});
```

- [ ] **Step 4: Add diagnostics to `installAppServerModelRequestPatch`**

Find `installAppServerModelRequestPatch`. In the `patch = async () => {` block, replace the success and failure handling. The full `patch` function body should become:

```swift
      try {
        const module = await loadCodexAppModule("app-server-manager-signals-");
        const candidates = Object.values(module).filter((value) => value && typeof value === "object");
        let patchedCount = 0;
        for (const candidate of candidates) {
          if (patchAppServerModelRequestClient(candidate)) patchedCount += 1;
          if (typeof candidate.sendRequest !== "function" && typeof candidate.get === "function") {
            try {
              if (patchAppServerModelRequestClient(candidate.get())) patchedCount += 1;
            } catch (_) {}
          }
        }
        if (patchedCount > 0) {
          window.__codexPlusAppServerModelRequestPatchInstalled = codexAppServerModelRequestPatchVersion;
          sendCodexPlusDiagnostic("appserver_request_patch_installed", { patchedCount: patchedCount });
        } else {
          sendCodexPlusDiagnostic("appserver_request_patch_not_found", {
            exportCount: Object.keys(module || {}).length,
            candidateCount: candidates.length,
          });
        }
      } catch (e) {
        sendCodexPlusDiagnostic("appserver_request_patch_failed", { error: String(e?.stack || e) });
      }
```

- [ ] **Step 5: Add diagnostics to `installModelJsonResponsePatch`**

Find `installModelJsonResponsePatch`. After `window.__codexPlusModelJsonResponsePatchInstalled = "1";`, add:

```js
      sendCodexPlusDiagnostic("json_response_patch_installed", {});
```

- [ ] **Step 6: Add diagnostics to `scheduleCodexModelWhitelistRefresh`**

Find `scheduleCodexModelWhitelistRefresh`. After `codexModelWhitelistRefreshUntil = Math.max(codexModelWhitelistRefreshUntil, Date.now() + durationMs);`, add:

```js
    sendCodexPlusDiagnostic("model_whitelist_refresh_scheduled", { durationMs: durationMs });
```

- [ ] **Step 7: Build to verify**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift build 2>&1 | tail -5`
Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
cd /Users/panando/ClaudeCode/APIbypass
git add CodexRouterCore/CDP/CDPInjectionScript.swift
git commit -m "feat(cdp): add diagnostic events to model whitelist patches"
```

---

## Task 10: Add diagnostic events to plugin patches

**Files:**
- Modify: `CodexRouterCore/CDP/CDPInjectionScript.swift`

- [ ] **Step 1: Add diagnostic to `installPluginMarketplacePatch`**

Find `installPluginMarketplacePatch`. After `window.__codexPluginMarketplacePatchInstalled = true;`, add:

```js
    sendCodexPlusDiagnostic("plugin_marketplace_patch_installed", {});
```

- [ ] **Step 2: Add diagnostic to `enablePluginEntry`**

Find `enablePluginEntry`. After `pluginButton.dataset.codexPluginEnabled = "true";` (inside the `if (pluginButton.dataset.codexPluginEnabled !== "true")` block), add:

```js
      sendCodexPlusDiagnostic("plugin_entry_unlocked", { spoofed: spoofed });
```

- [ ] **Step 3: Build to verify**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift build 2>&1 | tail -5`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
cd /Users/panando/ClaudeCode/APIbypass
git add CodexRouterCore/CDP/CDPInjectionScript.swift
git commit -m "feat(cdp): add diagnostic events to plugin patches"
```

---

## Task 11: Add CDP status indicator to UI

**Files:**
- Modify: `APIBypass/UI/Views/CodexAdaptorView.swift`
- Modify: `APIBypass/Core/LocalizationManager.swift`

- [ ] **Step 1: Add localization keys**

In `APIBypass/Core/LocalizationManager.swift`, find the `"codex_enhancements"` key (around line 498). Add immediately after it:

```swift
        "cdp_status_disconnected": [.chinese: "CDP: 未连接", .english: "CDP: Disconnected"],
        "cdp_status_connecting": [.chinese: "CDP: 连接中", .english: "CDP: Connecting"],
        "cdp_status_injected": [.chinese: "CDP: 已注入", .english: "CDP: Injected"],
        "cdp_status_failed": [.chinese: "CDP: 失败", .english: "CDP: Failed"],
```

- [ ] **Step 2: Add status indicator to enhancements card**

In `APIBypass/UI/Views/CodexAdaptorView.swift`, find the `enhancementsCard` computed property (around line 300). The card starts with `cardSection(header: ...) {`. Add a status row as the FIRST child inside the card body (before the plugin entry unlock HStack). The color mapping uses a local helper:

```swift
    private var cdpStatusColor: Color {
        switch codexAdaptor.cdpConnectionState {
        case .disconnected: return .secondary
        case .connecting, .connected: return .orange
        case .injected: return .green
        case .failed: return .red
        }
    }

    private var cdpStatusText: String {
        switch codexAdaptor.cdpConnectionState {
        case .disconnected: return L10n.t("cdp_status_disconnected")
        case .connecting, .connected: return L10n.t("cdp_status_connecting")
        case .injected: return L10n.t("cdp_status_injected")
        case .failed(let reason): return "\(L10n.t("cdp_status_failed")) — \(reason)"
        }
    }
```

Add these two computed properties to the `CodexAdaptorView` struct (place them near other computed helpers in the view).

Then in `enhancementsCard`, add as the first row inside the card body:

```swift
            HStack(spacing: 8) {
                Circle()
                    .fill(cdpStatusColor)
                    .frame(width: 8, height: 8)
                Text(cdpStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.bottom, 4)
```

- [ ] **Step 3: Build to verify**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift build 2>&1 | tail -5`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
cd /Users/panando/ClaudeCode/APIbypass
git add APIBypass/UI/Views/CodexAdaptorView.swift APIBypass/Core/LocalizationManager.swift
git commit -m "feat(ui): add CDP connection status indicator to enhancements card"
```

---

## Task 12: Run full test suite and manual verification

- [ ] **Step 1: Run full test suite**

Run: `cd /Users/panando/ClaudeCode/APIbypass && swift test 2>&1 | tail -10`
Expected: all tests pass, no regressions.

- [ ] **Step 2: Manual verification — diagnostic channel**

1. Launch APIBypass app
2. Start Codex adaptor (with enhancements enabled)
3. Launch Codex
4. Open APIBypass log panel (Codex adaptor view → Logs)
5. Verify `[CDP] script_loaded {}` appears
6. Verify `[CDP] settings_loaded {...}` appears
7. Verify `[CDP] catalog_loaded {"modelCount":N}` appears (N = number of configured models)
8. Verify one or more `*_installed` events appear (statsig, appserver_message, json_response, plugin_marketplace)

- [ ] **Step 3: Manual verification — connection state**

1. With Codex running, verify enhancements card shows green dot + "CDP: 已注入"
2. Quit Codex
3. Within ~6 seconds (2 poll cycles), verify dot turns gray + "CDP: 未连接"
4. Verify log shows `[CDP] Page disappeared, reconnecting`
5. Relaunch Codex
6. Within ~6 seconds, verify dot turns green again + "CDP: 已注入"

- [ ] **Step 4: Manual verification — port dynamic**

1. In APIBypass, change the Codex adaptor port from 15721 to 15722
2. Restart Codex adaptor
3. Restart Codex (so it picks up new debug port config — actually the CDP debug port is separate from the HTTP port; the HTTP port is what we changed)
4. Verify logs still show `[CDP] script_loaded` (meaning the injection script successfully reached `/cdp/diagnostic` on the new port)
5. Verify `/settings/get` and `/codex-model-catalog` also work on the new port

- [ ] **Step 5: Manual verification — failure event**

1. Temporarily edit `CDPInjectionScript.swift` to change `"app-server-manager-signals-"` to `"app-server-manager-BROKEN-"`
2. Build and run
3. Verify log shows `[CDP] appserver_request_patch_not_found {"exportCount":0,"candidateCount":0}` at INFO level (blue, not red)
4. Revert the change

---

## Self-Review Checklist

- [x] **Spec coverage:**
  - HTTP push diagnostics channel → Tasks 3 (pure functions) + 4 (route) + 8 (JS helper) + 9-10 (event points)
  - Port dynamicization → Task 1 (field) + Task 2 (populate) + Task 8 (JS `codexPlusBackendBase`)
  - Connection state → Task 5 (enum) + Task 6 (injector) + Task 7 (service polling) + Task 11 (UI)
  - Error handling (catch blocks report diagnostics) → Tasks 9-10
  - Log level mapping → Task 3 (`diagnosticLogLevel`)
  - TDD pure functions → Tasks 3, 5
- [x] **No placeholders:** every step has concrete code or commands. No "TBD", "add appropriate error handling", "similar to Task N".
- [x] **Type consistency:** `proxyPort: Int` in Task 1 (struct) → populated in Task 2 → read in Task 8 (`codexPlusBackendSettings.proxyPort`). `CDPConnectionState` in Task 5 (enum) → used in Task 6 (`connectionState` property) → Task 7 (`cdpConnectionState` published) → Task 11 (`cdpStatusColor`/`cdpStatusText`). `formatDiagnosticLogLine(event:detail:)` / `diagnosticLogLevel(for:)` in Task 3 → called in Task 4 (route). `snapshotState()` in Task 6 → called in Task 7.
- [x] **Safeguards:** all JS diagnostic calls wrapped in try/catch (Task 8 `sendCodexPlusDiagnostic` has outer try/catch). Route handler degrades gracefully (empty body → `event = "unknown"`, `detail = [:]`). CDP injection failure does not block HTTP proxy (Task 6 keeps existing `if config.cdpSettings.enhancementsEnabled` guard).
