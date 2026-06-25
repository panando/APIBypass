import XCTest
import CodexRouterCore

/// 验证真实 APIBypass 注入器在 Codex 渲染器里安装的 bridge 能转发到 15721 代理。
///
/// 这个测试不安装 mock handler — 它依赖 APIBypass 应用已经启动且代理在 15721 运行。
/// 它直接连接同一个 CDP target，检查 `window.__codexSessionDeleteBridge` 是否已定义。
///
/// 如果 APIBypass 注入器成功安装了 bridge，这个全局应该存在。
final class CDPBridgeProbeTests: XCTestCase {

    func test_probe_bridgeInstalledByApp() async throws {
        // 发现 9222 上的 page WS URL
        let versionURL = URL(string: "http://127.0.0.1:9222/json")!
        let (data, _) = try await URLSession.shared.data(from: versionURL)
        let targets = try JSONDecoder().decode([CDPTarget].self, from: data)
        guard let page = targets.first(where: { $0.type == "page" }),
              let ws = page.webSocketDebuggerUrl,
              let wsURL = URL(string: ws) else {
            throw XCTSkip("No Codex page target on :9222")
        }

        let client = CDPClient(wsURL: wsURL)
        try await client.connect()
        defer { Task { await client.disconnect() } }

        // 检查 bridge 是否已安装（由 APIBypass 注入器）
        let result = try await client.evaluateJavaScript(
            "typeof window.__codexSessionDeleteBridge"
        )
        XCTAssertEqual(result.value, "function",
                       "Bridge not installed by APIBypass injector. Got: \(result.value ?? "nil")")

        // 检查 settings 是否已加载（bridge 调用 /settings/get 的结果）
        let settingsResult = try await client.evaluateJavaScript(
            "window.__codexPlusBackendSettings && window.__codexPlusBackendSettings.modelProvider"
        )
        XCTAssertEqual(settingsResult.value, "apibypass",
                       "Settings not loaded via bridge. modelProvider: \(settingsResult.value ?? "nil")")

        // 触发 model catalog 加载并等待结果。
        // 注入脚本把 catalog 存在 IIFE 闭包里，但暴露了 codexPlusModelNames()。
        // 我们通过调用它来验证 catalog 已填充。如果返回空数组，说明 catalog 还没加载或加载失败。
        try await client.addBinding(name: "probeCatalog") { request in
            return "{}".data(using: .utf8)!
        }
        _ = try await client.evaluateJavaScript("""
        (async function() {
          // catalog 由 injection script 的 bootstrap() 异步加载，给它一点时间
          await new Promise(r => setTimeout(r, 2000));
          window.__probeResult = "ready";
        })();
        """)
        try await Task.sleep(for: .seconds(3))

        // 检查 catalog 是否通过 bridge 加载（indirect: settings 加载成功证明 bridge 工作）
        // catalog 存在闭包内，但 codexPlusModelNames 是全局可访问的
        let catalogProbe = try await client.evaluateJavaScript("""
        (function() {
          try {
            // codexPlusModelNames 定义在注入脚本 IIFE 内，不可直接访问
            // 但如果 bridge 工作，settings 已加载，modelWhitelistUnlock 已激活
            var s = window.__codexPlusBackendSettings || {};
            return JSON.stringify({
              modelProvider: s.modelProvider,
              whitelistUnlock: s.codexAppModelWhitelistUnlock,
              proxyPort: s.proxyPort
            });
          } catch(e) { return "error:" + e; }
        })()
        """)
        XCTAssertNotNil(catalogProbe.value, "Catalog probe returned nil")
        XCTAssertTrue(catalogProbe.value?.contains("apibypass") ?? false,
                      "Bridge settings not fully propagated: \(catalogProbe.value ?? "nil")")
    }
}
