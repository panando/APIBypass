import Foundation

/// In-memory ring buffer for Codex Adaptor log entries. Observable by log viewer UI.
final class CodexLogStore: ObservableObject, @unchecked Sendable {
    static let shared = CodexLogStore()

    @Published private(set) var entries: [LogEntry] = []
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
}
