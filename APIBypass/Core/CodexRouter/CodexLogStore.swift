import Foundation
import CodexRouterCore

/// Thread-safe ring buffer for Codex Adaptor log entries.
/// Not an ObservableObject — UI polls via snapshot() to avoid @Published
/// triggering Combine/SwiftUI/AutoLayout on background threads.
final class CodexLogStore: @unchecked Sendable {
    static let shared = CodexLogStore()

    private var entries: [LogEntry] = []
    private let maxEntries = 2000
    private let lock = NSLock()

    private init() {}

    /// Thread-safe append from any context.
    func append(level: DisplayLogLevel, message: String) {
        let entry = LogEntry(level: level, message: message)
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        lock.unlock()
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
