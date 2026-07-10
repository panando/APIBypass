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

/// Launches Codex.app / ChatGPT.app with `--remote-debugging-port` and waits for the CDP endpoint.
enum CodexAppLauncher {
    static let codexBundleId = "com.openai.codex"
    static let defaultCandidates = [
        "/Applications/Codex.app",
        "~/Applications/Codex.app",
        "/Applications/ChatGPT.app",
        "~/Applications/ChatGPT.app",
    ]

    /// Locate Codex/ChatGPT app in standard install locations. Returns the first match.
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

    /// Resolve the main executable name from the app bundle's Info.plist.
    /// Reads `CFBundleExecutable` and falls back to "Codex" if unavailable or suspicious.
    static func resolveExecutableName(appURL: URL) -> String {
        let plistPath = appURL.appendingPathComponent("Contents/Info.plist").path
        guard let plistData = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let executable = plist["CFBundleExecutable"] as? String,
              !executable.isEmpty,
              !executable.contains("/"),
              !executable.contains("\\") else {
            return "Codex"
        }
        return executable
    }

    /// Derive the app display name from a bundle URL (e.g., "ChatGPT" from ".../ChatGPT.app").
    static func appNameFromURL(_ appURL: URL) -> String {
        let dirname = appURL.deletingPathExtension().lastPathComponent
        return dirname.isEmpty ? "Codex" : dirname
    }

    /// Manual fallback command shown to the user.
    static func manualLaunchCommand(port: UInt16, appName: String = "Codex") -> String {
        "open -a \(appName) --args --remote-debugging-port=\(port) --remote-allow-origins=*"
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
            // Poll until the process actually exits (up to 5 seconds).
            // Fixed wait is unreliable - process exit time varies.
            let deadline = Date().addingTimeInterval(5.0)
            while Date() < deadline {
                if fs.runningApplication(bundleId: codexBundleId) == nil {
                    break // Process has exited
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
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
            // Use nanoseconds API to avoid Swift Issue #86204 cross-module specialization crash.
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
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
