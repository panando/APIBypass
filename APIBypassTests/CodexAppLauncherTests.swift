import XCTest
import AppKit
@testable import APIBypass

final class CodexAppLauncherTests: XCTestCase {

    // MARK: - Fake File System

    private struct FakeFS: CodexFileSystem {
        let existingPaths: Set<String>
        let runningBundleIds: Set<String>
        var terminateCalls: Int = 0

        func fileExists(atPath path: String) -> Bool {
            existingPaths.contains(path)
        }

        func runningApplication(bundleId: String) -> NSRunningApplication? {
            guard runningBundleIds.contains(bundleId) else { return nil }
            // 返回一个非 nil 的占位实例（测试只关心是否 nil）
            return NSRunningApplication()
        }

        func terminate(_ app: NSRunningApplication) -> Bool {
            true
        }
    }

    // MARK: - detectCodexAppPath

    func test_detectCodexAppPath_findsInApplications() {
        let fs = FakeFS(existingPaths: ["/Applications/Codex.app"], runningBundleIds: [])
        XCTAssertEqual(
            CodexAppLauncher.detectCodexAppPath(fs: fs)?.path,
            "/Applications/Codex.app"
        )
    }

    func test_detectCodexAppPath_findsInUserApplications() {
        let home = "/Users/test"
        let userApp = "\(home)/Applications/Codex.app"
        let fs = FakeFS(existingPaths: [userApp], runningBundleIds: [])
        XCTAssertEqual(
            CodexAppLauncher.detectCodexAppPath(fs: fs, home: home)?.path,
            userApp
        )
    }

    func test_detectCodexAppPath_prefersSystemApplicationsOverUser() {
        let home = "/Users/test"
        let userApp = "\(home)/Applications/Codex.app"
        let fs = FakeFS(
            existingPaths: ["/Applications/Codex.app", userApp],
            runningBundleIds: []
        )
        XCTAssertEqual(
            CodexAppLauncher.detectCodexAppPath(fs: fs, home: home)?.path,
            "/Applications/Codex.app"
        )
    }

    func test_detectCodexAppPath_returnsNilWhenNotFound() {
        let fs = FakeFS(existingPaths: [], runningBundleIds: [])
        XCTAssertNil(CodexAppLauncher.detectCodexAppPath(fs: fs))
    }

    // MARK: - ChatGPT.app detection (Task 2.1)

    func test_detectCodexAppPath_findsChatGPTApp() {
        let fs = FakeFS(existingPaths: ["/Applications/ChatGPT.app"], runningBundleIds: [])
        XCTAssertEqual(
            CodexAppLauncher.detectCodexAppPath(fs: fs)?.path,
            "/Applications/ChatGPT.app"
        )
    }

    func test_detectCodexAppPath_prefersCodexOverChatGPT() {
        let fs = FakeFS(
            existingPaths: ["/Applications/Codex.app", "/Applications/ChatGPT.app"],
            runningBundleIds: []
        )
        XCTAssertEqual(
            CodexAppLauncher.detectCodexAppPath(fs: fs)?.path,
            "/Applications/Codex.app"
        )
    }

    func test_detectCodexAppPath_findsChatGPTInUserApplications() {
        let home = "/Users/test"
        let userApp = "\(home)/Applications/ChatGPT.app"
        let fs = FakeFS(existingPaths: [userApp], runningBundleIds: [])
        XCTAssertEqual(
            CodexAppLauncher.detectCodexAppPath(fs: fs, home: home)?.path,
            userApp
        )
    }

    func test_detectCodexAppPath_returnsNilWhenNeitherExists() {
        let fs = FakeFS(existingPaths: ["/Applications/Other.app"], runningBundleIds: [])
        XCTAssertNil(CodexAppLauncher.detectCodexAppPath(fs: fs))
    }

    // MARK: - resolveExecutableName (Task 2.2)

    func test_resolveExecutableName_readsFromPlist() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let contentsDir = tempDir.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
          <key>CFBundleExecutable</key>
          <string>ChatGPT</string>
        </dict>
        </plist>
        """
        try plistContent.write(to: contentsDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        XCTAssertEqual(CodexAppLauncher.resolveExecutableName(appURL: tempDir), "ChatGPT")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_resolveExecutableName_fallsBackWhenPlistMissing() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(CodexAppLauncher.resolveExecutableName(appURL: tempDir), "Codex")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_resolveExecutableName_fallsBackWhenValueContainsPathSeparator() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let contentsDir = tempDir.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
          <key>CFBundleExecutable</key>
          <string>../Malicious</string>
        </dict>
        </plist>
        """
        try plistContent.write(to: contentsDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        XCTAssertEqual(CodexAppLauncher.resolveExecutableName(appURL: tempDir), "Codex")

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - manualLaunchCommand (Task 2.3)

    func test_manualLaunchCommand_defaultAppName() {
        XCTAssertEqual(
            CodexAppLauncher.manualLaunchCommand(port: 9222),
            "open -a Codex --args --remote-debugging-port=9222 --remote-allow-origins=*"
        )
    }

    func test_manualLaunchCommand_chatgptAppName() {
        XCTAssertEqual(
            CodexAppLauncher.manualLaunchCommand(port: 9222, appName: "ChatGPT"),
            "open -a ChatGPT --args --remote-debugging-port=9222 --remote-allow-origins=*"
        )
    }

    func test_manualLaunchCommand_customPort() {
        XCTAssertEqual(
            CodexAppLauncher.manualLaunchCommand(port: 9333),
            "open -a Codex --args --remote-debugging-port=9333 --remote-allow-origins=*"
        )
    }

    // MARK: - appNameFromURL

    func test_appNameFromURL_chatgpt() {
        let url = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        XCTAssertEqual(CodexAppLauncher.appNameFromURL(url), "ChatGPT")
    }

    func test_appNameFromURL_codex() {
        let url = URL(fileURLWithPath: "/Applications/Codex.app")
        XCTAssertEqual(CodexAppLauncher.appNameFromURL(url), "Codex")
    }
}
