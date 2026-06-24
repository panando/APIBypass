# CDP Injection Observability Design

**Date:** 2026-06-24
**Status:** Approved

## Problem

APIBypass 的 CDP 注入（`CodexAppInjector`）是 fire-and-forget——注入脚本有没有跑、跑到哪一步、哪个 patch 失败了，APP 完全不知道。之前几轮修改加了 Statsig patch、IPC 拦截、React state patch，但无法验证是否生效，出问题只能靠猜。

根因：注入脚本的诊断输出到 Codex 渲染进程的 DevTools console（`console.log("[CodexPlus] ...")`），APIBypass 收不到；`CodexAppInjector` 的 `injectIntoCodex()` catch 块是空的；连接状态是内部变量，UI 看不到。

## Solution

完全遵循 Codex Plus Plus 的诊断方案（HTTP push），加 CDP 连接状态暴露：

1. **诊断通道（HTTP push）** — 注入脚本移植 CPP 的 `sendCodexPlusDiagnostic(event, detail)`，POST 到 APIBypass 新增的 `POST /cdp/diagnostic` 端点。端点写 `CodexLogStore`，复用现有日志面板。
2. **连接状态暴露** — `CodexAppInjector` 暴露 `CDPConnectionState`（5 个状态），透传到 UI 显示状态灯。
3. **端口动态化** — `CDPInjectionSettings` 加 `proxyPort` 字段，通过 CDP `pushSettings` 注入，消除注入脚本里的硬编码端口。

## Architecture

### 诊断通道（移植 CPP）

**端点：** `POST /cdp/diagnostic`（在 `CodexRoutes.swift` 注册）

请求 body：
```json
{
  "event": "statsig_patch_installed",
  "detail": {"clientCount": 1},
  "location": "app://codex/...",
  "userAgent": "...",
  "timestamp": "2026-06-24T12:00:00.000Z"
}
```

处理：解析 body → 用纯函数 `formatDiagnosticLogLine` 格式化 → 用纯函数 `diagnosticLogLevel(for:)` 决定级别 → `CodexLogStore.shared.append`。

日志格式：`[CDP] {event} {detailJSON}`，例如 `[CDP] statsig_patch_installed {"clientCount":1}`。

**注入脚本侧：**

```js
function sendCodexPlusDiagnostic(event, detail) {
  const payload = {
    event,
    detail: detail || {},
    location: window.location?.href || "",
    userAgent: navigator.userAgent || "",
    timestamp: new Date().toISOString(),
  };
  try {
    fetch(codexPlusBackendBase() + "/cdp/diagnostic", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      keepalive: true,
    }).catch(() => {});
  } catch (_) {}
}
```

与 CPP 的差异：
- 砍掉 `navigator.sendBeacon` 降级（`fetch + keepalive` 够用，实测丢事件再加回来）
- 砍掉 `helperBase` 变量（用 `codexPlusBackendBase()` 从 `proxyPort` 动态拼）
- 砍掉 `hasBridge` 字段（我们没有 bridge 概念）
- 端口不硬编码（见下文"端口动态化"）

**端口动态化：**

注入脚本加：
```js
function codexPlusBackendBase() {
  const port = codexPlusBackendSettings.proxyPort || 15721;
  return "http://127.0.0.1:" + port;
}
```

所有 `fetch("http://127.0.0.1:15721/...")` 改成 `fetch(codexPlusBackendBase() + "/...")`。

时序：`CodexAppInjector.pushSettings()` 在 `evaluateJavaScript(codexPluginInjectionScript)` 之前执行（现有逻辑 line 76-79），注入脚本启动时 `window.__codexPlusBackendSettings` 已有 `proxyPort`。`fetchBackendSettings` 只用来刷新，不是首次获取。

### 事件清单

| 事件 | 触发时机 | detail | 日志级别 |
|---|---|---|---|
| `script_loaded` | 注入脚本执行到末尾 | `{version}` | info |
| `settings_loaded` | `fetchBackendSettings` 成功 | `{modelProvider, enhancementsEnabled}` | info |
| `catalog_loaded` | `loadCodexModelCatalog` 成功 | `{modelCount}` | info |
| `catalog_failed` | `loadCodexModelCatalog` 失败 | `{error}` | error |
| `statsig_patch_installed` | Statsig hook 安装 | `{clientCount}` | info |
| `statsig_patch_failed` | Statsig patch 异常 | `{error}` | error |
| `appserver_message_patch_installed` | `window.dispatchEvent` hook 安装 | `{}` | info |
| `appserver_request_patch_installed` | AppServer `sendRequest` hook 安装 | `{patchedCount}` | info |
| `appserver_request_patch_not_found` | webpack 模块未找到 | `{exportCount, candidateCount}` | info |
| `appserver_request_patch_failed` | AppServer patch 异常 | `{error}` | error |
| `json_response_patch_installed` | `Response.prototype.json` hook 安装 | `{}` | info |
| `model_whitelist_refresh_scheduled` | refresh 循环调度 | `{durationMs}` | info |
| `plugin_marketplace_patch_installed` | marketplace patch 安装 | `{}` | info |
| `plugin_entry_unlocked` | 入口解锁 | `{spoofed}` | info |

日志级别映射规则：
- `*_failed` → `.error`
- `*_not_found` → `.info`（webpack 模块还没加载是正常的）
- 其他 → `.info`

### 连接状态暴露

**状态机：**

```swift
public enum CDPConnectionState: Sendable, Equatable {
    case disconnected   // 未启动，或 Codex 未运行
    case connecting     // 正在连接 WebSocket
    case connected      // CDP 连上，尚未注入
    case injected       // 注入脚本执行成功
    case failed(String) // 失败，带原因
}
```

**状态转换点（对照 `CodexAppInjector` 现有代码）：**

| 代码位置 | 转换 | 日志 |
|---|---|---|
| `start()` 前 | → `.disconnected` | — |
| `injectIntoCodex()` 查询 targets | → `.connecting` | `[CDP] Connecting to debug port :{port}` |
| 无 Codex page target | 保持 `.disconnected` | `[CDP] No Codex page target found, will retry` |
| WebSocket 连接成功 | → `.connected` | `[CDP] WebSocket connected` |
| `evaluateJavaScript(script)` 成功 | → `.injected` | `[CDP] Script injected` |
| `evaluateJavaScript` 异常 | → `.failed(desc)` | `[CDP] Injection failed: {desc}` |
| `injectIntoCodex` catch | → `.failed(errorDesc)` | `[CDP] {errorDesc}` |
| `monitorAndReinject` 发现 page 消失 | → `.disconnected` → 重连 | `[CDP] Page disappeared, reconnecting` |
| `stop()` | → `.disconnected` | `[CDP] Injector stopped` |

**Actor 边界处理：** `CodexAppInjector` 是 actor，`@Published` 在 actor 外不能直接读。方案：`CodexAppInjector` 暴露 `public func snapshotState() async -> CDPConnectionState`；`CodexAdaptorService` 在现有 monitor 循环里定期 `await injector.snapshotState()`，写到自己的 `@Published var cdpConnectionState`。3 秒延迟可接受。

**UI 显示：** `CodexAdaptorView` 增强卡片顶部加一行：
- `.injected` → 绿点 + "CDP: 已注入"
- `.connected` / `.connecting` → 黄点 + "CDP: 连接中"
- `.disconnected` → 灰点 + "CDP: 未连接"
- `.failed(reason)` → 红点 + "CDP: 失败 — {reason}"

文案用纯函数 `localizedName() -> String`，颜色用 `indicatorColor() -> Color`，支持本地化。

## Error Handling

### 注入脚本侧

所有 patch 函数的 catch 块必须 `sendCodexPlusDiagnostic` 报告失败，不能静默。失败不中断后续 patch——Statsig 失败不影响 AppServer 尝试。

### Swift 端

1. `/cdp/diagnostic` 端点失败不影响注入脚本（`fetch().catch(() => {})` 静默）
2. CDP 注入失败不阻断 HTTP 代理（现有行为，保持）
3. CDP 连接断开自动重连（现有 `monitorAndReinject`，补状态转换 + 日志）
4. `pushSettings` 失败打日志但不改 `connectionState`（注入脚本会通过 `/settings/get` 拉取）

### 不做的事

- 不加自动回滚（Codex reload 自然清空 patch）
- 不加失败计数器 + 阈值禁用（YAGNI）
- 不加断路器

## Testing Strategy (TDD)

### 可单元测试的纯函数

1. **`CodexRequestHandler.formatDiagnosticLogLine(event:detail:) -> String`**
   - `formatDiagnosticLogLine("statsig_patch_installed", ["clientCount": 1])` → `[CDP] statsig_patch_installed {"clientCount":1}`
   - `formatDiagnosticLogLine("appserver_request_patch_not_found", ["exportCount":0,"candidateCount":0])` → `[CDP] appserver_request_patch_not_found {"exportCount":0,"candidateCount":0}`
   - 空 detail → `[CDP] script_loaded {}`

2. **`diagnosticLogLevel(for event:) -> DisplayLogLevel`**
   - `"catalog_failed"` → `.error`
   - `"statsig_patch_failed"` → `.error`
   - `"appserver_request_patch_not_found"` → `.info`
   - `"statsig_patch_installed"` → `.info`

3. **`CDPConnectionState.localizedName() -> String` + `indicatorColor() -> Color`**
   - `.disconnected` → "CDP: 未连接" / 灰
   - `.connecting` → "CDP: 连接中" / 黄
   - `.connected` → "CDP: 连接中" / 黄
   - `.injected` → "CDP: 已注入" / 绿
   - `.failed("reason")` → "CDP: 失败 — reason" / 红

### 不做单元测试（靠手动验证）

- CDP 连接/断开/重连流程（依赖真实 Codex 进程）
- 注入脚本 JS 逻辑（在 Swift 字符串里）
- `/cdp/diagnostic` 路由端到端（需要 HTTP server + curl）

### 手动验证清单

1. 启动 APIBypass + Codex，日志面板有 `[CDP] script_loaded`
2. 有各 patch 的 `*_installed` 事件
3. 临时改坏 webpack 模块名，有 `*_not_found` 事件（info 级别，不刷红）
4. 关 Codex，状态灯变红 + `[CDP] Page disappeared, reconnecting`
5. 重开 Codex，状态灯自动变绿
6. 改端口配置，注入脚本 fetch 用新端口

## File Structure

- **Modify:** `CodexRouterCore/CDP/CDPTypes.swift` — 加 `proxyPort` 字段；加 `CDPConnectionState` 枚举
- **Modify:** `CodexRouterCore/CDP/CodexAppInjector.swift` — 加 `connectionState` + `snapshotState()`；所有 catch 块打日志；状态转换点
- **Modify:** `CodexRouterCore/CDP/CDPInjectionScript.swift` — 加 `sendCodexPlusDiagnostic` + `codexPlusBackendBase()`；所有 fetch 用动态端口；所有 catch 块报诊断事件；加事件点
- **Modify:** `APIBypass/Core/CodexRouter/CodexRoutes.swift` — 加 `POST /cdp/diagnostic` 路由
- **Modify:** `APIBypass/Core/CodexRouter/CodexRequestHandler.swift` — 加 `formatDiagnosticLogLine` + `diagnosticLogLevel` 纯函数
- **Modify:** `APIBypass/Core/CodexAdaptorService.swift` — `handleSettingsGet` 填充 `proxyPort`；加 `cdpConnectionState` + 定期快照
- **Modify:** `APIBypass/UI/Views/CodexAdaptorView.swift` — 增强卡片顶部加 CDP 状态指示
- **Modify:** `APIBypass/Core/LocalizationManager.swift` — 加 `cdp_status_*` 本地化 key
- **Create:** `APIBypassTests/CDPDiagnosticsTests.swift` — 纯函数单元测试

## Out of Scope

- CDP `evaluate` 读回 `window.__codexPlus*` 状态（方案 C，未选定）
- `navigator.sendBeacon` 降级（实测丢事件再加）
- patch 失败自动回滚 / 断路器 / 失败计数器
- 历史连接状态记录
- service tier / ads / image overlay 等非模型功能的诊断事件
