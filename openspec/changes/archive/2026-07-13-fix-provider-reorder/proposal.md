## Why

配置页左侧边栏的提供商列表按 `apiProvider` 分成三个分组（Chat Completions / Anthropic / Responses），每个分组内拖拽条目排序后，最终落地顺序与拖动意图不符——所有分组（含第一个）都会错位。根因是 SwiftUI `.onMove` 给出的是**该分组过滤后子集的局部偏移**，而 `ConfigDataStore.moveProvider` 把局部偏移直接当成全局数组偏移去 `providers.move(...)`，存储顺序非分组聚类时即错位。

## What Changes

- `ConfigDataStore.moveProvider` 增加按 `apiProvider` 分组作用域参数，将局部偏移正确映射到全局存储槽位后再移动；语义限定为**分组内排序**，跨分组拖动钳制到本分组边界。
- `ConfigManager.moveProvider` 透传分组作用域参数。
- `ConfigWindow.providerList` 三个分组的 `.onMove` 各自传入对应的 `apiProvider` 字面量。
- 新增 `APIBypassTests/ProviderReorderTests.swift`，覆盖三分组组内移动、越界钳制、混合存储顺序等场景。

## Capabilities

### New Capabilities

- `provider-reorder`: 提供商列表在按协议分组的侧边栏中，通过拖拽在分组内重排并持久化顺序的行为契约（偏移语义、分组作用域、跨分组钳制、持久化）。

### Modified Capabilities

<!-- 无既有 spec，openspec/specs/ 当前为空 -->

## Impact

- 受影响代码：
  - `APIBypass/Core/ConfigDataStore.swift`（`moveProvider` 实现）
  - `APIBypass/Core/ConfigManager.swift`（`moveProvider` 透传）
  - `APIBypass/UI/ConfigWindow.swift`（三个 `.onMove` 调用点）
- 测试：`APIBypassTests/ProviderReorderTests.swift`（新增）
- 数据/持久化：沿用既有 `com.apibypass.providers` UserDefaults 键，存储格式不变，仅修正写入顺序。
- 不涉及 API key、base URL 等凭据路径；不修改 `Package.swift`。
- 范围外：`moveMapping` + `MappingDropDelegate` 疑似 off-by-one（见 `docs/provider-reorder-fix-design.md` 发现 5），本次不动。
