## Context

APIBypass 通过 CDP（`--remote-debugging-port=9222`）向 Codex.app（ChatGPT.app）注入一段 JS，把自有模型目录"塞"进 Codex 的模型选择栏。注入脚本（`CodexRouterCore/CDP/CDPInjectionScript.swift`）安装若干 hook：

- `json_response_patch`：拦截 `Response.prototype.json`（被动，响应侧）。
- `appserver_message_patch`：拦截 `window.dispatchEvent` 上的 `codex-message-from-view`/`mcp-request`（`model/list`）及其响应（被动，响应侧）。
- `statsig_patch`：拦截 Statsig `getDynamicConfig`，解锁模型白名单（被动，响应侧）。
- `appserver_request_patch`：拦截 app-server 客户端的 `sendRequest`（`list-models-for-host`）--**最直接的请求侧通道**，但依赖加载 `app-server-manager-signals-` webpack chunk。

注入生命周期由 `CodexAppInjector` 管理：`monitorInterval = 3` 秒轮询 CDP target，页面消失后重连重注入。

导出日志 `codexadaptor-logs-20260724-141211.txt` 显示：14:05（失败）与 14:11（成功）两次运行的诊断事件序列几乎一致--均 `catalog_loaded{modelCount:8}`，均缺少 `appserver_request_patch_installed` 与 `model_container_patched`。说明：(1) 请求侧通道（app-server patch）因 webpack chunk 未加载而始终未装上（`assets_available` 全空）；(2) 当前诊断只记录 hook **安装**，不记录 hook 是否**真正拦截到请求**，故无法直接区分两次运行的差异。差异只能来自时序竞争：Codex 启动时的首次模型拉取是否发生在 hook 安装之前。

## Goals / Non-Goals

**Goals:**

- Codex（含 ChatGPT.app）通过 APIBypass 启动或重启后，模型选择栏在数秒内显示 APIBypass 来源的模型，无需等待 5~10 分钟。
- 不依赖 Codex 自发的周期性刷新--注入完成后主动触发一次模型重拉，使已装 hook 必然命中。
- 恢复请求侧拦截通道（`appserver_request_patch`）：在 webpack chunk 加载后延迟安装。
- 提供可观测性，能从日志确认"hook 是否真正拦截到模型请求"以及修复效果。

**Non-Goals:**

- 不改写 Statsig 动态配置的取值策略（只沿用现有 `patchStatsigModelDynamicConfig`）。
- 不重构 React fiber 扫描方案（`patchReactModelState`/`patchObjectGraphForModels` 保持现状）。
- 不改上游代理转发行为（`CodexProxyServer`、`/v1/chat/completions` 链路不变）。
- 不改 `~/.codex/config.toml`、catalog 文件格式或 Keychain 凭据路径。

## Decisions

### 决策 1：重启后进入快轮询重注入（`CodexAppInjector`）

**选择**：监视器在检测到"Connection lost / 页面消失"后，进入快轮询阶段（间隔约 300~500ms），一旦发现新 CDP target 立即注入；注入成功后回到 3 秒稳态轮询。

**理由**：Codex.app 进程启动后 1~2 秒内即发起首次模型拉取。当前 3 秒轮询 + 连接开销导致 hook 安装滞后约 4 秒，几乎必然输掉竞争。稳态期无事可做，3 秒节奏省 CPU；但重连期需要抢时间，快轮询以最小代价缩短窗口。

**备选**：
- 全局把 `monitorInterval` 降到 1 秒：实现最简，但稳态期无谓轮询，且仍有最多 1 秒延迟。
- 用 `NSWorkspace.didLaunchApplicationNotification` 监听 ChatGPT.app 启动并立即触发一次探测：近乎零延迟，但 CDP target 在进程启动后仍需时间就绪，仍需轮询；且要绑定 bundle id 与注入器生命周期。可作为后续增强，当前以快轮询为底。

### 决策 2：注入完成后强制触发模型重拉（核心修复）

**选择**：在 `bootstrapModelWhitelist` 的 `ensureCodexModelWhitelistInstalls()` 之后，新增 `forceCodexModelListRefresh()`：

1. `loadCodexModelCatalog(true)` 强制刷新 APIBypass catalog，确保 `codexPlusModelNames()` 为最新。
2. 通过 `window.dispatchEvent` 派发一个 `codex-message-from-view` / `mcp-request` / `model/list` 请求（复刻选择栏打开时的请求形态），让 `appserver_message_patch` 拦截该出站请求（记下 request id）并拦截其响应、打 patch。
3. 调用 `scheduleCodexModelWhitelistRefresh` 安排一个**加长**的刷新窗口（约 10 秒），让 `runCodexModelWhitelistRefreshPass` 在异步响应返回期间持续重打 React 状态与重试 app-server patch。

**理由**：现有刷新只对**已存在**的 React 状态打 patch，无法恢复 Codex 已缓存的空列表。主动派发一次 `model/list` 请求，是把"等 Codex 自发重拉"变成"逼它现在就重拉"，使已装 hook 必然命中一次。加长刷新窗口用于兜住异步响应并覆盖决策 3 的重试。

**备选**：
- 纯 React fiber 重打（现状）：对缓存空列表无效，已排除。
- 直接调用 app-server 客户端发起 `list-models-for-host`：依赖决策 3 先装上请求侧 patch 才能拿到客户端引用，故只能作次级通道，不作主通道。
- 触发 Statsig 配置网络重拉：Statsig SDK 未暴露可靠的强制重拉入口，`getDynamicConfig` 返回的是缓存值，不可行。

### 决策 3：webpack 依赖 patch 的延迟重试

**选择**：`installAppServerModelRequestPatch` 在 chunk 不可用时不立即放弃，改为：

- 结合决策 2 加长的刷新窗口，让 `runCodexModelWhitelistRefreshPass` 在每个 tick 继续 calling `installAppServerModelRequestPatch`（现有逻辑已含此调用，只是窗口太短）。
- 额外用 `PerformanceObserver`（`entryTypes: ["resource"]`）监听新加载的 JS 资源，一旦观察到含 `app-server-manager-signals-` 的 URL 立即触发一次安装尝试；并以轻量轮询（约 2 秒、上限 30 秒）兜底，覆盖 observer 订阅前已加载的资源。

**理由**：`assets_available` 证明注入时 chunk 尚未加载，但 Codex 后续会加载它。延长窗口 + 资源监听可在 chunk 就绪的第一时间装上请求侧通道，把"碰运气"的响应侧补强为"主动拦截"的请求侧。

**备选**：
- 仅 `PerformanceObserver`、不加轮询：observer 只能捕获订阅之后的新条目，可能漏掉已加载资源，故仍需轮询兜底。
- 放弃请求侧 patch、只靠响应侧：现状已证明响应侧在竞争失败时无法恢复，不可接受。

### 决策 4：补充确认性诊断事件

**选择**：新增事件（均经现有 `/cdp/diagnostic` 路由写入 `CodexLogStore`）：

- `model_fetch_intercepted` { channel, modelCount, requestMethod }：在各调用点（`patchModelJsonResponse` / `patchMcpModelResponseData` / `patchAppServerModelResult` / `patchStatsigModelDynamicConfig`）真正改写模型容器时发出，标识命中通道--补上"安装 vs 拦截"的可观测性缺口。
- `forced_refresh_dispatched` { hasModels }：决策 2 派发请求时发出。
- `appserver_request_retry` { attempt, assetFound }：决策 3 重试时发出。

**理由**：当前日志无法解释"14:05 与 14:11 事件序列相同但结果不同"。这些事件让我们直接看到哪条通道真正拦到了请求、何时拦到，既验证根因假设，也度量修复效果。

**备选**：不加诊断、直接上修复--风险是若根因假设有偏差，无法定位为何仍偶发失败。故诊断先行（与 tasks 中的首批任务对齐）。

## Risks / Trade-offs

- [风险] 派发 `model/list` 请求未必被 Codex app-server 路由/响应 -> 缓解：仅当 `shouldPatchModels()` 且 catalog 有模型时派发；派发后观察窗口内是否出现 `model_fetch_intercepted`/`model_container_patched`，未命中则记录诊断（见 Open Questions 1）；同时保留决策 3 的请求侧通道作后备。
- [风险] `app-server-manager-signals-` chunk 命名随 Codex 版本变动 -> 缓解：`assets_available` 已记录全部匹配模式；将模式抽取为常量并容忍模糊匹配；版本升级时需回归（见 Open Questions 2）。
- [风险] 快轮询 + 加长刷新窗口增加 CPU -> 缓解：快轮询仅在重连期短暂生效；刷新窗口虽加长但 tick 间隔 1 秒且 `runCodexModelWhitelistRefreshPass` 轻量；沿用现有 debounce 防止 mutation 风暴。
- [权衡] 派发伪造请求可能与 Codex 自身选择栏打开的请求重复 -> 可接受：`appserver_message_patch` 已按 request id 去重响应打 patch；重复响应幂等。
- [风险] 诊断事件过多 -> 缓解：拦截类事件按请求计次而非按 mutation；沿用 `CodexLogStore` 的 `verboseMode` 去重。

## Migration Plan

- 纯客户端注入脚本 + Swift 注入器改动，无数据迁移、无 API 变更、无持久化格式变化。
- 随下一次 DMG 构建发布；回滚即还原注入脚本与 `CodexAppInjector` 节奏参数。
- 验证：手动复现（退出 Codex -> 经 APIBypass 重启 -> 观察选择栏数秒内出现模型）+ 查看新增诊断事件是否出现 `model_fetch_intercepted`。

## Open Questions

1. 经 `window.dispatchEvent({type:"codex-message-from-view", detail:{type:"mcp-request", request:{method:"model/list", ...}}})` 派发的请求，是否真能让 Codex app-server 返回模型列表？需实现后实证（tasks 首批任务）。若无效，改用决策 3 装好的 app-server 客户端直接发起 `list-models-for-host`，或寻找其他触发路径。
2. `app-server-manager-signals-` chunk 命名在当前及近期 ChatGPT.app 版本是否稳定？需确认；若不稳定，需设计更鲁棒的模块发现方式。
3. 快轮询间隔与刷新窗口时长的具体取值，需实测在 CPU 与延迟间折中。
4. 14:05 vs 14:11 的差异是否确由"首次拉取时机"决定，将由决策 4 的诊断事件最终确认。
