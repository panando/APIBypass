> **验收通过 2026-07-24**：手动复现验收（6.4 连测 3 次、6.5、3.3、4.6、5.5）均由用户确认通过；2.1/2.2/2.3 为 Path A 并入 6.4。全部任务完成。

## 1. 确认性诊断事件

- [x] 1.1 在 `CDPInjectionScript.swift` 各模型容器改写调用点（`patchModelJsonResponse` / `patchMcpModelResponseData` / `patchAppServerModelResult` / `patchStatsigModelDynamicConfig`）发出 `model_fetch_intercepted`，detail 含 `channel` 与 `modelCount`
- [x] 1.2 新增 `forced_refresh_dispatched { hasModel }` 与 `appserver_request_retry { attempt, assetFound }` 事件
- [x] 1.3 必要时在 `CodexRequestHandler.diagnosticLogLevel` 为新事件补充级别映射（默认 `.info`）— 默认 `.info` 已覆盖，补单测断言

## 2. 验证根因假设（先确认再动手修）

> **Path A（用户选择"一次到位"）**：诊断与修复一同发布。本组不单独构建仅含诊断的版本；根因确认并入第 6 组验收，由 `model_fetch_intercepted` 日志在复现时观察。

- [x] 2.1 用 `swift build`（或 `build-dmg.sh`）构建仅含新诊断、未含修复的版本 — *Path A 跳过：诊断与修复一同构建于 6.2*
- [x] 2.2 复现：退出 Codex 经 APIBypass 重启，导出日志 — *Path A：并入 6.4 复现*
- [x] 2.3 确认假设：成功运行出现 `model_fetch_intercepted`、失败运行无该事件（区分"仅安装"与"已拦截"），验证 Open Question 4；若假设不成立，回到 design 重新评估 — *Path A：由 6.4 验收时观察确认*

## 3. 重启后快轮询重注入（`CodexAppInjector.swift`）

- [x] 3.1 检测到页面消失 / "Connection lost" 后，将监视器切换为快轮询间隔（约 300~500ms）— 实现为 400ms
- [x] 3.2 新 CDP target 出现并注入成功后，恢复 3 秒稳态轮询
- [x] 3.3 验证：退出 Codex 经 APIBypass 重启，确认 hook 在新页面可用后 2 秒内重装（spec 需求 4）— *需手动验收*

## 4. 注入完成后强制触发模型重拉（`CDPInjectionScript.swift`，核心修复）

- [x] 4.1 新增 `forceCodexModelListRefresh()`：先 `loadCodexModelCatalog(true)` 强制刷新 catalog
- [x] 4.2 通过 `window.dispatchEvent` 派发 `codex-message-from-view` / `mcp-request` / `model/list` 请求，触发 app-server 响应
- [x] 4.3 派发时发出 `forced_refresh_dispatched { hasModels }`
- [x] 4.4 在 `bootstrapModelWhitelist` 的 `ensureCodexModelWhitelistInstalls()` 之后调用 `forceCodexModelListRefresh()`
- [x] 4.5 为强制重拉场景将 `scheduleCodexModelWhitelistRefresh` 窗口加长至约 10 秒，兜住异步响应
- [x] 4.6 验证 Open Question 1：确认派发的 `model/list` 被 Codex 路由并被 `appserver_message` 通道拦截（日志见 `model_fetch_intercepted`）；若未路由，改用 app-server 客户端直接发起 `list-models-for-host`（依赖第 5 组装好的请求侧 patch）— *需手动验收*

## 5. 请求侧 patch 延迟重试（`CDPInjectionScript.swift`）

- [x] 5.1 用 `PerformanceObserver`（`entryTypes: ["resource"]`）监听 `app-server-manager-signals-` chunk 加载，加载后触发 `installAppServerModelRequestPatch()`
- [x] 5.2 增加有界轮询（约 2 秒、上限约 30 秒）兜底重试 `installAppServerModelRequestPatch()`，覆盖订阅前已加载的资源
- [x] 5.3 每次重试发出 `appserver_request_retry { attempt, assetFound }`
- [x] 5.4 将 chunk 名模式抽取为常量；保持 `assets_available` 记录全部匹配模式以便排障
- [x] 5.5 验证：在注入时 assets 为空的运行中，确认 chunk 加载后最终出现 `appserver_request_patch_installed`（spec 需求 3）— *需手动验收*

## 6. 测试、构建与最终验收

- [x] 6.1 在 `APIBypassTests/` 下为可单测部分（chunk 名匹配、刷新调度逻辑）新增/扩展测试，mock 化、不依赖外部服务 — 新增 `CodexAppInjectorTests`（`monitorInterval(for:)` 快/慢区间）、扩展 `CDPDiagnosticsTests`（新事件 -> `.info`）；chunk 名匹配为 JS 内部逻辑，由集成测试 + 手动复现诊断覆盖
- [x] 6.2 用 `swift build`（或 `build-dmg.sh`）构建，确认无回归 — `swift build` 通过
- [x] 6.3 运行 `swift test` — 全部通过；唯一失败 `CDPBridgeProbeTests` 为预存在的环境依赖（需 app 在 :9222/:15721 运行），stash 改动后同样失败，与本次无关
- [x] 6.4 手动复现验收：退出 Codex 经 APIBypass 重启，连续 3 次确认选择栏在 5 秒内出现 APIBypass 模型（spec 需求 1、4）— *需手动验收*
- [x] 6.5 确认选择栏暂空时直接发起会话仍能按 slug 解析模型（spec 需求 1 场景 3）— *需手动验收*
- [x] 6.6 更根目录 `release_note.md`
