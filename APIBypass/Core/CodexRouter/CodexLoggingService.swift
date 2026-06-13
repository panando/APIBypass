import Foundation
import OSLog

/// Log level for the Codex Adaptor logging service.
enum CodexLogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    static func < (lhs: CodexLogLevel, rhs: CodexLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }

    var prefix: String {
        switch self {
        case .debug: return "[DEBUG]"
        case .info: return "[INFO]"
        case .warning: return "[WARN]"
        case .error: return "[ERROR]"
        }
    }
}

/// Log category for organizing log messages.
enum CodexLogCategory: String, Sendable {
    case proxy = "Proxy"
    case provider = "Provider"
    case transformer = "Transformer"
    case config = "Config"
    case general = "General"
}

/// Structured logging service for Codex Adaptor.
actor CodexLoggingService {
    static let shared = CodexLoggingService()

    private let logger = Logger(subsystem: "com.apibypass.codexadaptor", category: "General")
    private var minimumLevel: CodexLogLevel = .info
    private var logFileURL: URL?
    private var fileHandle: FileHandle?

    private init() {}

    func setMinimumLevel(_ level: CodexLogLevel) {
        minimumLevel = level
    }

    func enableFileLogging(to path: String? = nil) throws {
        let logPath = path ?? defaultLogPath()
        logFileURL = URL(fileURLWithPath: logPath)

        let directory = logFileURL!.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        fileHandle = try FileHandle(forWritingTo: logFileURL!)
    }

    func disableFileLogging() {
        fileHandle?.closeFile()
        fileHandle = nil
        logFileURL = nil
    }

    func defaultLogPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.codex/logs/proxy.log"
    }

    func info(
        _ message: String,
        category: CodexLogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }

    func error(
        _ message: String,
        category: CodexLogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }

    private func log(
        _ message: String,
        level: CodexLogLevel,
        category: CodexLogCategory,
        file: String,
        function: String,
        line: Int
    ) {
        guard level >= minimumLevel else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "\(timestamp) \(level.prefix) [\(category.rawValue)] \(fileName):\(line) - \(message)"

        logger.log(level: level.osLogType, "\(logMessage)")

        // Also append to CodexLogStore for UI
        let displayLevel: DisplayLogLevel
        switch level {
        case .debug: displayLevel = .debug
        case .info: displayLevel = .info
        case .warning: displayLevel = .warn
        case .error: displayLevel = .error
        }
        CodexLogStore.shared.append(level: displayLevel, message: message)

        if let handle = fileHandle {
            let data = (logMessage + "\n").data(using: .utf8)!
            handle.write(data)
        }
    }
}
