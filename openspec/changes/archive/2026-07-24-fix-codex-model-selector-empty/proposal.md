## Why

通过 APIBypass 重启 Codex（ChatGPT.app）后，模型选择栏频繁出现"自定义"但列表为空--期望显示 APIBypass 来源的模型。此时直接发消息可正常对话（模型按 slug 正确解析），但选择栏要等 5~10 分钟以上才出现具体模型，严重影响可用性。

根因（基于导出日志 `codexadaptor-logs-20260724-141211.txt` 的分析，标注为待验证假设）：

1. **时序竞争**：Codex.app 启动时会拉取模型列表（Statsig 动态配置 + app-server `list-models-for-host` + HTTP fetch）。APIBypass 的 CDP 注入脚本通过 3 秒轮询监视器（`CodexAppInjector.monitorInterval`）在 Codex 进程启动约 4 秒后才完成 hook 安装。若 Codex 的首次拉取发生在 hook 安装之前，hook 错过该次请求，Codex 缓存空列表且短期内不再重拉--选择栏保持空。
2. **app-server 请求拦截 patch 装不上**：`installAppServerModelRequestPatch` 依赖加载 `app-server-manager-signals-` webpack chunk，而注入时该 chunk 尚未加载（日志 `assets_available` 全部为空数组），导致最直接的拦截通道（`list-models-for-host` 请求拦截）缺失，只剩被动的响应侧 patch（`json_response` / `appserver_message` / `statsig`）--这些只有当 Codex 在 patch 装好之后**主动**发起请求时才会触发。
3. **刷新窗口过短且被动**：`scheduleCodexModelWhitelistRefresh` 仅运行约 2.5 秒，且只对**已存在**的 React 状态重新打 patch，不会强制 Codex 重新拉取。一旦 Codex 已缓存空列表，该刷新无法恢复；用户观察到的"10 分钟后出现"是 Codex 自身周期性重拉（如 Statsig 刷新）恰好命中已装 hook 的结果。

日志证据：失败的 14:05 运行与成功的 14:11 运行，诊断事件序列几乎完全一致（均 `catalog_loaded{modelCount:8}`，均缺少 `appserver_request_patch_installed` 与 `model_container_patched`），差异纯粹是竞争结果--而当前诊断事件只记录 patch 安装，不记录"是否真正拦截到请求"，因此无法直接区分。本变更的首批任务将补充确认性诊断以验证该假设。

## What Changes

- **降低重启后的重注入延迟**：`CodexAppInjector` 在检测到页面消失（"Connection lost"）后，以更高频率轮询新页面直至注入完成，缩短 Codex 启动拉取与 hook 安装之间的竞争窗口。
- **注入完成后强制触发模型重拉**：在 `bootstrapModelWhitelist` 完成 patch 安装后，主动触发 Codex 的模型列表拉取路径（重新派发 `model/list` mcp-request / 触发 `list-models-for-host` / 强制刷新 catalog 并驱动选择栏重渲染），使已装 hook 必然拦截到一次请求，不再依赖 Codex 自发刷新。
- **webpack 依赖 patch 延迟重试**：`installAppServerModelRequestPatch` 在 chunk 不可用时安排重试，待 `app-server-manager-signals-` 资源加载后（轮询或监听资源加载事件）再次尝试安装，恢复最直接的请求拦截通道。
- **补充确认性诊断事件**：新增"实际拦截到模型请求"类事件（记录命中的通道与模型数），以验证根因假设并度量修复效果。
- 非目标：不改写 Statsig 动态配置取值策略、不重构 React fiber 扫描方案、不改上游代理转发行为。

## Capabilities

### New Capabilities

- `codex-model-injection`: APIBypass 将自有模型目录可靠注入 Codex.app 模型选择栏的行为契约--覆盖正常启动与（重启后的）时序竞争场景下的可见性、强制重拉时机、webpack 依赖 patch 的延迟重试，以及可观测性要求。

### Modified Capabilities

<!-- openspec/specs/ 当前仅有 provider-reorder，与本变更无关；无既有 spec 需修改 -->

## Impact

- 受影响代码：
  - `CodexRouterCore/CDP/CodexAppInjector.swift`（重启后重注入延迟与轮询节奏）
  - `CodexRouterCore/CDP/CDPInjectionScript.swift`（强制重拉、app-server patch 延迟重试、新增诊断事件）
  - 诊断路由/日志（`CodexRoutes.swift` / `CodexRequestHandler.swift` 的事件词汇表，若新增事件需要）
- 测试：在 `APIBypassTests/` 下新增/扩展覆盖刷新与重试逻辑的可单测部分（mock 化，不依赖外部服务）。
- 不涉及 API key、base URL 等凭据路径；不修改 `Package.swift`。
- 范围外：Statsig 配置取值、React fiber 扫描策略、上游代理转发。
