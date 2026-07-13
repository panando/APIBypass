## 1. 测试先行（红）

- [x] 1.1 新建 `APIBypassTests/ProviderReorderTests.swift`，`@MainActor` + 沿用 `ConfigManagerTests` 的 delete-clear `setUp` 模式
- [x] 1.2 写"分组内前移"用例：混合存储 `[A(o),B(o),C(a),D(o)]`，openai 分组 `source={1},dest=0` → 断言 `[D,A,B,C]`（对应 spec scenario「同分组内前移」）
- [x] 1.3 写"分组内后移"用例：`[A(o),C(a),B(o),D(o)]`，openai `source={0},dest=3` → 断言 `[C,B,D,A]`（scenario「同分组内后移」）
- [x] 1.4 写"混合存储顺序下第一分组"用例：`[A(o),C(a),B(o)]`，openai 移 B 到 offset 0 → 断言 `[B,C,A]`
- [x] 1.5 写"跨分组钳制到本组末尾"用例：`[A(o),B(o),C(a),D(a)]`，openai `source={0},dest=2` → 断言 `[B,A,C,D]`
- [x] 1.6 写"持久化并可恢复"用例：移动后 new `ConfigManager` + `refresh()`，断言顺序一致
- [x] 1.7 写"空分组不操作"用例：`[A(o),B(o)]` 对 anthropic onMove → 断言不变
- [x] 1.8 写"source 越界丢弃"用例：source 含越界索引 → 断言合法部分移动、不崩溃
- [x] 1.9 运行 `swift test` 确认全部失败（红）

## 2. 实现（绿）

- [x] 2.1 `ConfigDataStore.moveProvider` 增加 `apiProvider: APIProvider` 参数，改用 design D2 算法（提取组 → `group.move` → 回填原槽位），保留 `guard !slots.isEmpty` 兜底
- [x] 2.2 `ConfigManager.moveProvider` 透传 `apiProvider:` 参数
- [x] 2.3 `ConfigWindow.swift` 三个 `.onMove` 各自传入 `.openai` / `.anthropic` / `.responses`
- [x] 2.4 运行 `swift test` 确认全部通过（绿）

## 3. 真机帧确认（design D4）

- [x] 3.1 在某 `.onMove` 临时加 `print(source, destination)`，构建 DMG 真机拖动三个分组，确认 `.onMove` 给的是分组局部偏移
- [x] 3.2 验证后撤除 print
- [x] 3.3 若帧假设错误，回退为"全局偏移直接 `providers.move`"并改查 storage 顺序问题（触发 design D4 风险缓解分支）

## 4. 手动验证

- [x] 4.1 用 `build-dmg.sh` 构建 DMG
- [x] 4.2 三分组各拖动一次，确认落地顺序符合预期且持久化
- [x] 4.3 重启 app 确认顺序保持

## 5. 收尾

- [x] 5.1 回填 design.md「Open Questions」中 D4 真机确认结果
- [x] 5.2 更新 `release_note.md`
- [x] 5.3 同步 README（如用户可见行为有变化）
