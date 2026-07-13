## ADDED Requirements

### Requirement: 分组内拖拽排序落地正确

提供商列表按 `apiProvider` 分组展示时，`.onMove` 给出的分组局部偏移 SHALL 被正确映射到全局存储数组，使条目在所属分组内移动后落地顺序与拖动意图一致。

#### Scenario: 同分组内前移

- **WHEN** 全局存储为 `[A(openai), B(openai), C(anthropic), D(openai)]`，对 `openai` 分组执行 `.onMove` 移动 D 到分组内 offset 0（`source={2}, destination=0`，相对过滤后子集 `[A,B,D]`）
- **THEN** 全局存储变为 `[D, A, C, B]`（openai 占用槽位不变、C 原位不动）；按 section 过滤后 openai=`[D,A,B]`、anthropic=`[C]`

#### Scenario: 同分组内后移

- **WHEN** 全局存储为 `[A(openai), C(anthropic), B(openai), D(openai)]`，对 `openai` 分组执行移动 A 到分组末尾（`source={0}, destination=3`，相对过滤后子集 `[A,B,D]`）
- **THEN** 全局存储变为 `[B, C, D, A]`（C 原位不动）；按 section 过滤后 openai=`[B,D,A]`、anthropic=`[C]`

#### Scenario: 混合存储顺序下第一个分组也正确

- **WHEN** 全局存储顺序为混合（非分组聚类）`[A(openai), C(anthropic), B(openai)]`，对 `openai` 分组执行移动 B 到分组内 offset 0
- **THEN** 全局存储变为 `[B, C, A]`，C 原位不变

### Requirement: 跨分组拖动钳制到本分组边界

拖动意图跨越不同 `apiProvider` 分组时，系统 SHALL 钳制到本分组边界，不改变条目的 `apiProvider`，不把条目落入其它分组。

#### Scenario: 拖向其它分组被钳制到本组末尾

- **WHEN** 全局存储为 `[A(openai), B(openai), C(anthropic), D(anthropic)]`，对 `openai` 分组执行 `source={0}, destination=2`（超出本分组长度 2）
- **THEN** 全局存储变为 `[B, A, C, D]`，A 落到 `openai` 分组末尾，不进入 `anthropic` 分组，C/D 原位不变

### Requirement: 排序结果持久化

移动后的全局顺序 SHALL 立即持久化到 `com.apibypass.providers` UserDefaults 键，重启后保持。

#### Scenario: 持久化并可恢复

- **WHEN** 对某分组执行一次合法移动后，重新从持久化存储加载 providers
- **THEN** 加载得到的顺序与移动后的全局顺序一致

### Requirement: 空分组或越界索引静默不操作

当目标 `apiProvider` 在全局数组中无对应条目，或 `source` 索引越界时，系统 SHALL 静默不修改存储，不崩溃。

#### Scenario: 空分组不操作

- **WHEN** 全局存储为 `[A(openai), B(openai)]`，对 `anthropic` 分组执行任意 `onMove`
- **THEN** 全局存储保持 `[A, B]` 不变

#### Scenario: source 越界丢弃

- **WHEN** 对某分组执行 `source` 含越界索引的 `onMove`
- **THEN** 越界索引被丢弃，合法部分正常移动，不崩溃
