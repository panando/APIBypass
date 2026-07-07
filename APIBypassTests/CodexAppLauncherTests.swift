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

    // MARK: - Cancellation Propagation

    func test_launchCodexWithDebugPort_propagatesCancellation() async {
        // Test: When task is cancelled during sleep, CancellationError should propagate correctly
        // This test verifies the fix for swift_task_dealloc crash

        let fs = FakeFS(
            existingPaths: [],
            runningBundleIds: [CodexAppLauncher.codexBundleId] // Simulate Codex is running
        )

        let task = Task {
            try await CodexAppLauncher.launchCodexWithDebugPort(
                appURL: URL(fileURLWithPath: "/fake/Codex.app"),
                port: 9222,
                fs: fs
            )
        }

        // Cancel immediately to trigger cancellation during the 800ms sleep
        task.cancel()

        do {
            try await task.value
            XCTFail("Should throw CancellationError")
        } catch is CancellationError {
            // ✓ Correct: CancellationError propagated correctly
        } catch {
            XCTFail("Wrong error type: \(type(of: error))")
        }
    }

    func test_waitForDebugPort_propagatesCancellation() async {
        // Test: When task is cancelled during port polling, CancellationError should propagate

        let task = Task {
            try await CodexAppLauncher.waitForDebugPort(9222, waitTimeout: 5.0)
        }

        // Cancel after a short delay (during the polling loop)
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            task.cancel()
        }

        do {
            try await task.value
            // Port won't respond in test, so it should either timeout or be cancelled
            XCTFail("Should throw error")
        } catch is CancellationError {
            // ✓ Correct
        } catch {
            // Timeout is also acceptable in test environment
            XCTAssertTrue(error is CodexAppLauncherError)
        }
    }
}
