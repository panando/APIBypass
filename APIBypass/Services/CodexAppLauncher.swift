import Foundation
import AppKit

/// File system + process abstraction for testable Codex app launch logic.
protocol CodexFileSystem: Sendable {
    func fileExists(atPath path: String) -> Bool
    func runningApplication(bundleId: String) -> NSRunningApplication?
    func terminate(_ app: NSRunningApplication) -> Bool
}

struct DefaultCodexFileSystem: CodexFileSystem {
    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func runningApplication(bundleId: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    func terminate(_ app: NSRunningApplication) -> Bool {
        app.terminate()
    }
}

enum CodexAppLauncherError: Error, LocalizedError {
    case appNotFound
    case launchFailed(String)
    case portStillClosedAfterLaunch(UInt16)

    var errorDescription: String? {
        switch self {
        case .appNotFound:
            return L10n.t("codex_launch_app_not_found")
        case .launchFailed(let msg):
            return "\(L10n.t("codex_launch_failed")): \(msg)"
        case .portStillClosedAfterLaunch(let port):
            return "\(L10n.t("codex_launch_port_timeout")) (port \(port))"
        }
    }
}

/// Launches Codex.app with `--remote-debugging-port` and waits for the CDP endpoint.
enum CodexAppLauncher {
    static let codexBundleId = "com.openai.codex"
    static let defaultCandidates = ["/Applications/Codex.app", "~/Applications/Codex.app"]

    /// Locate Codex.app in standard install locations. Returns the first match.
    static func detectCodexAppPath(
        fs: CodexFileSystem = DefaultCodexFileSystem(),
        home: String = NSHomeDirectory()
    ) -> URL? {
        for candidate in defaultCandidates {
            let resolved = candidate.hasPrefix("~")
                ? (home as NSString).appendingPathComponent(String(candidate.dropFirst(2)))
                : candidate
            if fs.fileExists(atPath: resolved) {
                return URL(fileURLWithPath: resolved)
            }
        }
        return nil
    }

    /// Manual fallback command shown to the user.
    static func manualLaunchCommand(port: UInt16) -> String {
        "open -a Codex --args --remote-debugging-port=\(port) --remote-allow-origins=*"
    }

    /// Probe `/json/version` on the debug port. Returns true if a CDP endpoint responds.
    static func isDebugPortListening(_ port: UInt16, timeout: TimeInterval = 2.0) async -> Bool {
        let urls = [
            URL(string: "http://127.0.0.1:\(port)/json/version"),
            URL(string: "http://[::1]:\(port)/json/version")
        ].compactMap { $0 }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)

        for url in urls {
            do {
                let (_, resp) = try await session.data(from: url)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    return true
                }
            } catch {
                continue
            }
        }
        return false
    }

    /// Launch (or relaunch) Codex.app with `--remote-debugging-port=<port>`.
    /// If Codex is already running, terminates it first (Electron requires the flag at process start).
    static func launchCodexWithDebugPort(
        appURL: URL,
        port: UInt16,
        fs: CodexFileSystem = DefaultCodexFileSystem()
    ) async throws {
        if let existing = fs.runningApplication(bundleId: codexBundleId) {
            _ = fs.terminate(existing)
            // Wait for termination. Task.sleep throws CancellationError if cancelled,
            // which will propagate correctly to the caller.
            try await Task.sleep(for: .milliseconds(800))
        }

        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--remote-debugging-port=\(port)", "--remote-allow-origins=*"]
        config.activates = true

        do {
            try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        } catch {
            throw CodexAppLauncherError.launchFailed(error.localizedDescription)
        }
    }

    /// Poll the debug port until it responds, up to `waitTimeout` seconds.
    static func waitForDebugPort(
        _ port: UInt16,
        pollInterval: TimeInterval = 0.5,
        waitTimeout: TimeInterval = 15.0
    ) async throws {
        let deadline = Date().addingTimeInterval(waitTimeout)
        while Date() < deadline {
            if await isDebugPortListening(port) { return }
            // Task.sleep throws CancellationError if cancelled, which propagates correctly.
            try await Task.sleep(for: .seconds(pollInterval))
        }
        throw CodexAppLauncherError.portStillClosedAfterLaunch(port)
    }

    /// Orchestrate: detect → probe → (optional confirm) → launch → wait.
    /// `onNeedConfirm` is called when Codex is already running; return false to abort.
    /// `onProgress` is called with status messages for the UI.
    static func ensureCodexRunningWithDebugPort(
        port: UInt16,
        fs: CodexFileSystem = DefaultCodexFileSystem(),
        onNeedConfirm: @MainActor () async -> Bool,
        onProgress: @MainActor (String) -> Void
    ) async throws {
        await onProgress(L10n.t("codex_launch_progress_detect"))
        guard let appURL = detectCodexAppPath(fs: fs) else {
            throw CodexAppLauncherError.appNotFound
        }

        if fs.runningApplication(bundleId: codexBundleId) != nil {
            let ok = await onNeedConfirm()
            if !ok { return }
        }

        await onProgress(L10n.t("codex_launch_progress_launch"))
        try await launchCodexWithDebugPort(appURL: appURL, port: port, fs: fs)

        await onProgress(L10n.t("codex_launch_progress_wait"))
        try await waitForDebugPort(port)
    }
}
