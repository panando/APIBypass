import XCTest
@testable import APIBypass

@MainActor
final class ProviderReorderTests: XCTestCase {
    private var configManager: ConfigManager!

    override func setUp() async throws {
        try await super.setUp()
        configManager = ConfigManager()
        await configManager.refresh()
        // Clear shared store so each test starts with a clean slate
        for provider in configManager.providers {
            await configManager.deleteProvider(provider.id)
        }
    }

    /// 便捷构造 provider
    private func make(_ name: String, _ type: APIProvider) -> ProviderConfig {
        ProviderConfig(name: name, apiProvider: type, baseURL: type.defaultBaseURL)
    }

    /// 按当前 configManager.providers 的 name 顺序返回，便于断言
    private func nameSequence() -> [String] {
        configManager.providers.map(\.name)
    }

    // MARK: - 分组内拖拽排序落地正确

    /// scenario「同分组内前移」
    /// 全局 [A(o),B(o),C(a),D(o)]，openai 子集 [A,B,D]，D 前移到 offset 0
    /// D 在子集中是 index 2，移动到 0 → 子集 [D,A,B]。
    /// D2 不变量：openai 占用槽位 {0,1,3} 不变，回填后 C 原位不动 → 全局 [D,A,C,B]。
    /// 视觉（按 section 过滤）：openai=[D,A,B], anthropic=[C]。
    func testMoveWithinGroupForward() async throws {
        await configManager.addProvider(make("A", .openai))
        await configManager.addProvider(make("B", .openai))
        await configManager.addProvider(make("C", .anthropic))
        await configManager.addProvider(make("D", .openai))

        // openai 子集 [A,B,D]，把 D(index 2) 移到 0
        await configManager.moveProvider(.openai, from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(nameSequence(), ["D", "A", "C", "B"])
    }

    /// scenario「同分组内后移」
    /// 全局 [A(o),C(a),B(o),D(o)]，openai 子集 [A,B,D]，A 后移到末尾(offset 3)
    /// A(index 0) 移到 3 → 子集 [B,D,A]。
    /// openai 占用槽位 {0,2,3} 不变，C 原位不动 → 全局 [B,C,D,A]。
    func testMoveWithinGroupBackward() async throws {
        await configManager.addProvider(make("A", .openai))
        await configManager.addProvider(make("C", .anthropic))
        await configManager.addProvider(make("B", .openai))
        await configManager.addProvider(make("D", .openai))

        await configManager.moveProvider(.openai, from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(nameSequence(), ["B", "C", "D", "A"])
    }

    /// scenario「混合存储顺序下第一分组也正确」
    /// 全局 [A(o),C(a),B(o)]，openai 子集 [A,B]，B 前移到 offset 0
    /// B(index 1) 移到 0 → 子集 [B,A] → 全局 [B,C,A]
    func testMoveInFirstGroupWithMixedStorage() async throws {
        await configManager.addProvider(make("A", .openai))
        await configManager.addProvider(make("C", .anthropic))
        await configManager.addProvider(make("B", .openai))

        await configManager.moveProvider(.openai, from: IndexSet(integer: 1), to: 0)

        XCTAssertEqual(nameSequence(), ["B", "C", "A"])
    }

    // MARK: - 跨分组拖动钳制到本分组边界

    /// scenario「拖向其它分组被钳制到本组末尾」
    /// 全局 [A(o),B(o),C(a),D(a)]，openai 子集 [A,B](长度2)
    /// source={0}, dest=2（超出子集长度2，即用户拖向 anthropic 分组）
    /// Array.move 把 A 移到末尾 → 子集 [B,A] → 全局 [B,A,C,D]
    func testCrossGroupDragClampsToEndOfGroup() async throws {
        await configManager.addProvider(make("A", .openai))
        await configManager.addProvider(make("B", .openai))
        await configManager.addProvider(make("C", .anthropic))
        await configManager.addProvider(make("D", .anthropic))

        // dest=2 超出 openai 子集长度(2)，等价于拖到本组末尾之后
        await configManager.moveProvider(.openai, from: IndexSet(integer: 0), to: 2)

        XCTAssertEqual(nameSequence(), ["B", "A", "C", "D"])
    }

    // MARK: - 排序结果持久化

    /// scenario「持久化并可恢复」
    func testPersistenceAfterMove() async throws {
        await configManager.addProvider(make("A", .openai))
        await configManager.addProvider(make("B", .openai))
        await configManager.addProvider(make("C", .anthropic))

        await configManager.moveProvider(.openai, from: IndexSet(integer: 1), to: 0)

        // 模拟 app 重启
        let restarted = ConfigManager()
        await restarted.refresh()

        XCTAssertEqual(restarted.providers.map(\.name), ["B", "A", "C"])
    }

    // MARK: - 空分组或越界索引静默不操作

    /// scenario「空分组不操作」
    /// 全局 [A(o),B(o)]，对 anthropic 分组执行任意 onMove（anthropic 子集为空）
    func testEmptyGroupNoOp() async throws {
        await configManager.addProvider(make("A", .openai))
        await configManager.addProvider(make("B", .openai))

        await configManager.moveProvider(.anthropic, from: IndexSet(integer: 0), to: 0)

        XCTAssertEqual(nameSequence(), ["A", "B"])
    }

    /// scenario「source 越界丢弃」
    /// openai 子集 [A,B]，source 含合法(0)+越界(5)，dest=2(末尾)
    /// 越界 5 被丢弃，A 移到末尾 → 子集 [B,A] → 全局 [B,A,C]
    func testSourceOutOfRangeDropped() async throws {
        await configManager.addProvider(make("A", .openai))
        await configManager.addProvider(make("B", .openai))
        await configManager.addProvider(make("C", .anthropic))

        var source = IndexSet()
        source.insert(0)
        source.insert(5)  // 越界，应被丢弃
        await configManager.moveProvider(.openai, from: source, to: 2)

        XCTAssertEqual(nameSequence(), ["B", "A", "C"])
    }
}
