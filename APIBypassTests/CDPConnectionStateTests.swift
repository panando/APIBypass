import XCTest
import CodexRouterCore
@testable import APIBypass

final class CDPConnectionStateTests: XCTestCase {

    func test_localizedName_disconnected() {
        XCTAssertEqual(CDPConnectionState.disconnected.localizedName, "CDP: 未连接")
    }

    func test_localizedName_connecting() {
        XCTAssertEqual(CDPConnectionState.connecting.localizedName, "CDP: 连接中")
    }

    func test_localizedName_connected() {
        XCTAssertEqual(CDPConnectionState.connected.localizedName, "CDP: 连接中")
    }

    func test_localizedName_injected() {
        XCTAssertEqual(CDPConnectionState.injected.localizedName, "CDP: 已注入")
    }

    func test_localizedName_failed_includesReason() {
        let state = CDPConnectionState.failed("WebSocket timeout")
        XCTAssertEqual(state.localizedName, "CDP: 失败 — WebSocket timeout")
    }
}
