import Foundation
import OSLog
import CodexRouterCore

/// Thread-safe ring buffer for Codex Adaptor log entries.
/// Also writes to macOS system log (unified logging).
final class CodexLogStore: @unchecked Sendable {
    static let shared = CodexLogStore()

    private var entries: [LogEntry] = []
    private let maxEntries = 2000
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.apibypass.codexadaptor", category: "CodexAdaptor")

    /// Verbose mode: when true, logs all events; when false, only errors and non-duplicate events.
    private var verboseMode: Bool = true
    /// Last message for deduplication in non-verbose mode.
    private var lastMessage: String?

    private init() {}

    func setVerboseMode(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        verboseMode = enabled
        if enabled {
            lastMessage = nil
        }
    }

    /// Thread-safe append from any context.
    func append(level: DisplayLogLevel, message: String) {
        lock.lock()
        defer { lock.unlock() }

        // In non-verbose mode: skip non-error messages that are duplicates of the last message
        if !verboseMode && level != .error {
            if message == lastMessage {
                return
            }
            lastMessage = message
        }

        let entry = LogEntry(level: level, message: message)
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }

        // Also write to system log
        switch level {
        case .debug: logger.debug("\(message)")
        case .info: logger.info("\(message)")
        case .warn: logger.warning("\(message)")
        case .error: logger.error("\(message)")
        }
    }

    /// Convenience: append info-level message.
    func info(_ message: String) {
        append(level: .info, message: message)
    }

    /// Clear all entries.
    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    /// Thread-safe snapshot for UI polling.
    func snapshot() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

extension CodexLogStore: CDPLogger {
    func logInfo(_ message: String) { info(message) }
    func logError(_ message: String) { append(level: .error, message: message) }
}
