import XCTest
@testable import CodexRouterCore

final class PickCodexTargetTests: XCTestCase {

    // MARK: - Helpers

    private func makeTarget(
        id: String = "1",
        type: String = "page",
        title: String,
        url: String,
        wsURL: String? = "ws://127.0.0.1:9222/devtools/page/1"
    ) -> CDPTarget {
        CDPTarget(
            id: id,
            type: type,
            title: title,
            url: url,
            webSocketDebuggerUrl: wsURL
        )
    }

    // MARK: - ChatGPT desktop page matching (Task 1.1)

    func test_pickCodexTarget_matchesChatGPTDesktopPage_chatgptCom() {
        let targets = [makeTarget(title: "ChatGPT", url: "https://chatgpt.com/")]
        let result = pickCodexTarget(targets)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "ChatGPT")
    }

    func test_pickCodexTarget_matchesChatGPTDesktopPage_chatgptComPath() {
        let targets = [makeTarget(title: "ChatGPT", url: "https://chatgpt.com/c/abc123")]
        let result = pickCodexTarget(targets)
        XCTAssertNotNil(result)
    }

    func test_pickCodexTarget_matchesChatGPTDesktopPage_chatOpenaiCom() {
        let targets = [makeTarget(title: "ChatGPT", url: "https://chat.openai.com/")]
        let result = pickCodexTarget(targets)
        XCTAssertNotNil(result)
    }

    func test_pickCodexTarget_matchesChatGPTDesktopPage_chatOpenaiComPath() {
        let targets = [makeTarget(title: "ChatGPT", url: "https://chat.openai.com/c/xyz")]
        let result = pickCodexTarget(targets)
        XCTAssertNotNil(result)
    }

    func test_pickCodexTarget_matchesChatGPTDesktopPage_dataTextHtml() {
        let targets = [makeTarget(
            title: "ChatGPT",
            url: "data:text/html;charset=utf-8,%3Ctitle%3EChatGPT%3C/title%3E"
        )]
        let result = pickCodexTarget(targets)
        XCTAssertNotNil(result)
    }

    func test_pickCodexTarget_matchesChatGPTDesktopPage_caseInsensitiveTitle() {
        let targets = [makeTarget(title: "chatgpt", url: "https://chatgpt.com/")]
        let result = pickCodexTarget(targets)
        XCTAssertNotNil(result)
    }

    // MARK: - "ChatGPT for Chrome" extension rejection (Task 1.2)

    func test_pickCodexTarget_rejectsChatGPTForChromeExtension() {
        // "ChatGPT for Chrome" has a different title — not exactly "ChatGPT"
        let targets = [makeTarget(title: "ChatGPT for Chrome", url: "chrome-extension://abc/")]
        let result = pickCodexTarget(targets)
        XCTAssertNil(result)
    }

    func test_pickCodexTarget_rejectsChatGPTWithUnrecognizedURL() {
        // Title matches but URL is not in the whitelist
        let targets = [makeTarget(title: "ChatGPT", url: "https://example.com/chat")]
        let result = pickCodexTarget(targets)
        XCTAssertNil(result)
    }

    // MARK: - No fallback to first page (Task 1.3)

    func test_pickCodexTarget_returnsNilForUnrecognizedPages() {
        let targets = [makeTarget(title: "Some App", url: "https://some.app/")]
        let result = pickCodexTarget(targets)
        XCTAssertNil(result)
    }

    func test_pickCodexTarget_returnsNilForDevToolsPage() {
        let targets = [makeTarget(title: "DevTools", url: "devtools://devtools/bundled/inspector.html")]
        let result = pickCodexTarget(targets)
        XCTAssertNil(result)
    }

    func test_pickCodexTarget_returnsNilWhenNoPagesWithWebSocket() {
        let targets = [makeTarget(title: "ChatGPT", url: "https://chatgpt.com/", wsURL: nil)]
        let result = pickCodexTarget(targets)
        XCTAssertNil(result)
    }

    // MARK: - Legacy "codex" keyword match preserved

    func test_pickCodexTarget_matchesLegacyCodexKeyword() {
        let targets = [makeTarget(title: "Codex", url: "https://codex.test/")]
        let result = pickCodexTarget(targets)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "Codex")
    }

    func test_pickCodexTarget_prefersCodexKeywordOverChatGPT() {
        let targets = [
            makeTarget(id: "1", title: "ChatGPT", url: "https://chatgpt.com/"),
            makeTarget(id: "2", title: "Codex", url: "app://codex"),
        ]
        let result = pickCodexTarget(targets)
        XCTAssertEqual(result?.id, "2")
    }
}
