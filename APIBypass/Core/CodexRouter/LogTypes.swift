import SwiftUI

/// A single log entry for the Codex Adaptor log viewer.
struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: String
    let level: DisplayLogLevel
    let message: String

    init(level: DisplayLogLevel, message: String) {
        self.timestamp = ISO8601DateFormatter().string(from: Date())
        self.level = level
        self.message = message
    }
}

/// Log level with color coding for the UI.
enum DisplayLogLevel: String, Sendable {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"

    var color: Color {
        switch self {
        case .debug: return .secondary
        case .info:  return .blue
        case .warn:  return .orange
        case .error: return .red
        }
    }
}
