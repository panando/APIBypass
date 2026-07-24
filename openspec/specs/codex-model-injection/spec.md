# Codex Model Injection

## Purpose

在 CDP（Chrome DevTools Protocol）注入场景下，确保 Codex.app 的模型选择栏在（重）启动后及时显示 APIBypass 来源的模型，并通过请求侧拦截、延迟安装、页面重注入和诊断区分等手段解决时序竞争导致的空列表问题。

## Requirements

### Requirement: 模型选择栏在 Codex（重）启动后及时显示 APIBypass 模型

系统 SHALL 确保 Codex.app 的模型选择栏在 CDP 页面可用于注入后的 5 秒内显示 APIBypass 来源的模型--无论 Codex 自身的启动模型拉取是否先于注入 hook 安装完成。该要求对首次启动与退出后重启均成立。

#### Scenario: 首次启动及时显示
- **WHEN** 通过 APIBypass 启动 Codex 且 CDP 页面对注入器可用
- **THEN** 在 5 秒内模型选择栏列出 APIBypass 来源的模型（而非仅显示"自定义"且列表为空）

#### Scenario: 退出后重启且竞争失败时仍能恢复
- **WHEN** Codex 被退出后经 APIBypass 重新启动，且 Codex 的启动模型拉取在 hook 安装之前完成（竞争失败）
- **THEN** 在注入完成后的 5 秒内选择栏仍填充 APIBypass 来源的模型，无需等待 Codex 自发的周期性刷新

#### Scenario: 选择栏暂空不影响对话
- **WHEN** 选择栏在恢复前暂时为空
- **THEN** 直接发起会话仍能按 slug 正确解析配置的模型（保留既有行为）

### Requirement: 注入完成后主动触发模型重拉

在注入 bootstrap 完成、hook 已安装后，系统 SHALL 在同一注入会话内主动通过被拦截的通道触发一次模型列表重拉，而非仅依赖 Codex 自发的周期性刷新。

#### Scenario: 派发重拉请求
- **WHEN** bootstrap 完成且 catalog 中至少有一个 APIBypass 模型
- **THEN** 系统触发一次模型列表重拉请求，且该行为可在诊断中观测

#### Scenario: 缓存空列表时被拦截并重填
- **WHEN** Codex 在 hook 安装前已缓存空模型列表
- **THEN** 触发的重拉产生一个被 hook 拦截的响应，并据此重填选择栏

### Requirement: 请求侧拦截在模块加载后延迟安装

当请求侧拦截所需的 app-server webpack 模块在注入时尚未加载时，系统 SHALL 在该模块加载后安装请求侧 patch，而非放弃安装。

#### Scenario: 注入时模块不可用
- **WHEN** 注入时 app-server 相关 webpack chunk 尚未加载
- **THEN** 系统在 chunk 加载后安装请求侧 patch，恢复对 list-models-for-host 的请求侧拦截

#### Scenario: 注入时模块已可用
- **WHEN** 注入时该 chunk 已加载
- **THEN** 请求侧 patch 在 bootstrap 期间立即安装

### Requirement: 页面丢失后以低延迟重注入

在 Codex 页面消失（如用户退出 Codex）后，注入器 SHALL 以最小延迟重新连接并注入新页面，使 hook 在新页面的启动模型拉取之前就位。

#### Scenario: 重启后重注入
- **WHEN** Codex 页面消失后出现新的 Codex 页面
- **THEN** 注入器在新页面可用后的 2 秒内重新安装 hook

### Requirement: 诊断区分 hook 安装与实际拦截

系统 SHALL 在模型请求被实际拦截（并标识拦截通道）时发出诊断事件，与仅记录 hook 安装的事件相区分，使时序竞争的结果可在日志中观测。

#### Scenario: 拦截被记录
- **WHEN** 任一已安装 hook 改写了模型列表响应
- **THEN** 发出标识拦截通道与模型数量的诊断事件

#### Scenario: 已安装但未拦截可区分
- **WHEN** hook 已安装但尚未拦截到任何模型请求
- **THEN** 不发出拦截类诊断事件，使"仅安装"与"已拦截"可区分