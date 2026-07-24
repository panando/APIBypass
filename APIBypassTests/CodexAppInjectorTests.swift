import XCTest
import CodexRouterCore

final class CodexAppInjectorTests: XCTestCase {

    // MARK: - monitorInterval(for:)

    /// Stable states (connected / injected) use the slow 3s interval so the
    /// injector idles without burning CPU once a page is injected.
    func test_monitorInterval_stableStates_useSlowInterval() {
        XCTAssertEqual(CodexAppInjector.monitorInterval(for: .connected), 3)
        XCTAssertEqual(CodexAppInjector.monitorInterval(for: .injected), 3)
    }

    /// Reconnecting states (disconnected / connecting / failed) use the fast
    /// 400ms interval so a new Codex page is re-injected within the 2s spec
    /// target after the previous page disappeared.
    func test_monitorInterval_reconnectingStates_useFastInterval() {
        XCTAssertEqual(CodexAppInjector.monitorInterval(for: .disconnected), 0.4)
        XCTAssertEqual(CodexAppInjector.monitorInterval(for: .connecting), 0.4)
        XCTAssertEqual(CodexAppInjector.monitorInterval(for: .failed("timeout")), 0.4)
    }

    /// The fast interval must leave room to re-inject within 2s (spec need 4)
    /// and must be strictly shorter than the slow interval so reconnect
    /// actually accelerates.
    func test_monitorInterval_fastIntervalWithinSpec() {
        let fast = CodexAppInjector.monitorInterval(for: .disconnected)
        let slow = CodexAppInjector.monitorInterval(for: .injected)
        XCTAssertLessThan(fast, 2.0, "Fast interval must leave room to re-inject within 2s")
        XCTAssertLessThan(fast, slow, "Fast interval must be shorter than the slow interval")
    }
}
