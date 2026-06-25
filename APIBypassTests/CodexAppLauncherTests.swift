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

    // MARK: - manualLaunchCommand

    func test_manualLaunchCommand_format() {
        XCTAssertEqual(
            CodexAppLauncher.manualLaunchCommand(port: 9222),
            "open -a Codex --args --remote-debugging-port=9222 --remote-allow-origins=*"
        )
    }

    func test_manualLaunchCommand_customPort() {
        XCTAssertEqual(
            CodexAppLauncher.manualLaunchCommand(port: 9333),
            "open -a Codex --args --remote-debugging-port=9333 --remote-allow-origins=*"
        )
    }
}
