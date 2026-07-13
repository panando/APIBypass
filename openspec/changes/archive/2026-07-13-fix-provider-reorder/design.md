## Context

配置页左侧边栏把提供商按 `apiProvider` 分成三个 `Section`（Chat Completions / Anthropic / Responses），每个 Section 内 `ForEach(filtered).onMove`。SwiftUI `.onMove` 回调给出的 `source/destination` 是**该 Section 过滤后子集的局部偏移**；而 `ConfigDataStore.moveProvider`（`ConfigDataStore.swift:117-121`）直接把这组局部偏移喂给 `providers.move(fromOffsets:toOffset:)` 操作**全局数组**——把局部偏移当成了全局偏移。当全局存储顺序非分组聚类时（增删后常见），偏移错位，表现为所有分组拖动后顺序都不对。

当前 `moveProvider` 实现：

```swift
func moveProvider(from source: IndexSet, to destination: Int) {
    ensureInitialized()
    providers.move(fromOffsets: source, toOffset: destination)
    saveProvidersSync()
}
```

测试隔离：`ConfigDataStore` 是 `static let shared` 单例 actor，`ensureInitialized` 一次性置位、读写真实 `UserDefaults.standard` 的 `com.apibypass.providers` 键。现有 `ConfigManagerTests` 用 `setUp` 里循环 delete 清空——本设计沿用该模式。

详细探索记录见 `docs/provider-reorder-fix-design.md`。

## Goals / Non-Goals

**Goals:**

- 让三分组内拖拽排序落地顺序与拖动意图一致，并持久化。
- 语义限定为**分组内排序**：条目只能在本 `apiProvider` 分组内移动。
- 跨分组拖动钳制到本分组边界（不改变 `apiProvider`，不跨协议）。
- 改动最小化、聚焦三条路径（store / manager / 三个 `.onMove`）。

**Non-Goals:**

- 不允许跨分组拖动（会带来"协议变不变"歧义）。
- 不修 `moveMapping` + `MappingDropDelegate` 的疑似 off-by-one（独立路径，范围外，见发现 5）。
- 不改存储格式或 UserDefaults 键。
- 不改 UI 信息架构（不合并 Section）。

## Decisions

### D1：偏移作用域参数 = `apiProvider`，而非 providerId 或隐式推断

`moveProvider` 增加 `apiProvider: APIProvider` 参数，三个 `.onMove` 各自传入字面量枚举。

**备选 A（隐式推断）**：从 `source` 反查全局索引推断类型。问题：`source` 是局部偏移，无全局索引可查，循环依赖。
**备选 B（View 层翻译偏移）**：在 View 层算全局偏移再传入。问题：View 层操作 `@Published` 快照，与 actor 内瞬时态可能不同步，翻译易错。

**选 `apiProvider` 字面量**：与 `moveMapping(providerId:...)` 传 scope 参数的风格一致；翻译在 actor 内操作真实 `providers` 状态；View 层改动最小（每个 `.onMove` 多一个字面量）。

### D2：算法 = 提取组 → `group.move` → 回填原槽位（非手动偏移翻译）

```swift
func moveProvider(_ type: APIProvider, from source: IndexSet, to destination: Int) {
    ensureInitialized()
    let slots = providers.indices.filter { providers[$0].apiProvider == type }  // 升序全局槽位
    guard !slots.isEmpty else { return }
    var group = providers.filter { $0.apiProvider == type }                      // 组内顺序
    group.move(fromOffsets: source, toOffset: destination)                       // 帧交给 Array.move
    for (i, slot) in slots.enumerated() { providers[slot] = group[i] }           // 回填到原槽位
    saveProvidersSync()
}
```

**关键不变量**：组内排列不改变"组占用哪些全局槽位"——只是把组内元素在这些固定槽位间重排。`.onMove` 给的 `source/destination` 就是"相对该组过滤数组、after-removal 帧"，而 `group` 正好是那个过滤数组，`Array.move` 期待的也是 after-removal 帧——语义天然对齐，零手动偏移算术。回填时槽位集合不变，非组元素原封不动。

**备选（放弃）**：照搬 `moveMapping` 的 `groupIndices[destination]` 手动翻译。
**放弃理由（发现 1）**：`moveMapping` 走的是 `ProviderDetailView` 自定义 `.onDrop` + `MappingDropDelegate`（`ProviderDetailView.swift:389-413`），`source/destination` 由 drop 委托手算，与 `.onMove` 偏移语义**不是同一套**，且无测试覆盖。它既不能佐证"`.onMove` 给分组局部偏移"，也不能当"正确算法"照抄；其手动翻译的 `+1` 偏移还有 off-by-one 风险（见发现 5）。

### D3：clamp 自动满足，不写显式 clamp 代码

`Array.move` 对 `toOffset ∈ [0...count]` 都能正确处理（越界即落到组末尾），SwiftUI 又把 `.onMove` 的 `destination` 约束在该 Section 范围内。两者叠加，跨分组拖动天然被钳制到本分组边界——无需额外 clamp 逻辑。仅保留 `guard !slots.isEmpty else { return }` 作兜底。

### D4：`.onMove` 偏移帧需真机确认（实现期一次性验证）

TDD 能锁定 store 层行为，但锁不了 SwiftUI 实际给什么帧。`.onMove` 在 `Section { ForEach{}.onMove }` 里给"相对该 ForEach 数据集合的偏移"是 SwiftUI 既定行为，但这是正确性根脉。实现时加一行临时 `print(source, destination)` 在真机拖一下确认是分组局部帧，验证后撤除。

## Risks / Trade-offs

- **[`.onMove` 帧假设错误]** → 若 SwiftUI 实际给全局偏移而非分组局部，D2 的 `group.move` 会双重错位。**缓解**：D4 的临时 print 真机确认；若假设错，回退为"全局偏移直接 `providers.move`"并改查 storage 顺序问题。
- **[async 刷新视觉回弹]** → `Task { await moveProvider }` 完成后 `refresh()` 触发 List 重绘，发生 clamp 时会有一次回弹跳动。**缓解**：与 mappings 侧既有行为一致，非本次引入；可接受。
- **[测试污染本机 UserDefaults]** → 单例 actor + 真实 `UserDefaults.standard`，测试新增的 provider 在本机 app 短暂可见直到下次启动被清。**缓解**：`setUp` 循环 delete 清空；属既有问题，范围外。
- **[`moveMapping` off-by-one 未修]** → 映射拖动可能存在"瞄准中间落到末尾"。**缓解**：独立路径，不影响本次修复；已在 `docs/provider-reorder-fix-design.md` 发现 5 留 note，后续单独查。

## Migration Plan

无数据迁移。存储格式与 UserDefaults 键不变，仅修正写入顺序。回滚：还原 `ConfigDataStore.moveProvider` / `ConfigManager.moveProvider` / 三个 `.onMove` 三处改动即可，无副作用。

## Open Questions

- ~~D4 的真机帧确认结果：`.onMove` 是否确为分组局部偏移？~~ **已确认**：真机拖动三分组后顺序均正确。D2 算法按"分组局部偏移"处理得到正确结果，反证 SwiftUI `.onMove` 给的确实是分组局部偏移，假设成立。无需触发 D4 风险缓解分支。（注：临时 print 因 stdout 日志管道未落盘，未拿到数值佐证，但端到端结果已等价验证。）
