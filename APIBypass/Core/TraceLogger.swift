import Foundation

/// 落盘 trace 日志，用于调试流式翻译丢包问题。
/// 写入 ~/Library/Logs/com.apibypass.app/trace/trace.log，每次请求用 reqId 串联上下游 SSE 事件。
/// 每次 app 启动时清理并重建 trace 目录（由 startServer() 触发 shared 访问）。
final class TraceLogger {
    static let shared = TraceLogger()

    /// trace 根目录：~/Library/Logs/com.apibypass.app/trace/
    static var traceDirectory: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("com.apibypass.app", isDirectory: true)
            .appendingPathComponent("trace", isDirectory: true)
    }

    /// body dump 目录：trace/debug/
    static var debugDirectory: URL {
        traceDirectory.appendingPathComponent("debug", isDirectory: true)
    }

    private let queue = DispatchQueue(label: "apibypass.trace.logger")
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter

    private init() {
        let fm = FileManager.default
        let dir = TraceLogger.traceDirectory
        let debugDir = TraceLogger.debugDirectory

        // 清理上次遗留：若 trace 目录存在，整体删除
        if fm.fileExists(atPath: dir.path) {
            try? fm.removeItem(at: dir)
        }
        // 重建 trace/ 与 debug/ 子目录
        try? fm.createDirectory(at: debugDir, withIntermediateDirectories: true)

        let logPath = dir.appendingPathComponent("trace.log").path
        fm.createFile(atPath: logPath, contents: nil)
        self.fileHandle = FileHandle(forWritingAtPath: logPath)
        self.fileHandle?.seekToEndOfFile()

        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    static func newReqId() -> String {
        String(UUID().uuidString.prefix(8))
    }

    func log(_ reqId: String, _ msg: String) {
        let ts = dateFormatter.string(from: Date())
        let line = "[\(ts)] [req=\(reqId)] \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async { [weak self] in
            self?.fileHandle?.write(data)
        }
    }

    /// 记录请求体（截断到 maxChars，避免日志爆炸）
    func logBody(_ reqId: String, label: String, data: Data, maxChars: Int = 4000) {
        let body = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
        let truncated: String
        if body.count > maxChars {
            truncated = String(body.prefix(maxChars)) + "…<truncated \(body.count - maxChars) chars>"
        } else {
            truncated = body
        }
        log(reqId, "━━━ \(label) ━━━")
        log(reqId, truncated)
    }

    /// 记录完整请求体（不截断），用于需要完整对照实验的场景
    func logBodyFull(_ reqId: String, label: String, data: Data) {
        let body = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
        log(reqId, "━━━ \(label) (full, \(body.count) chars) ━━━")
        log(reqId, body)
    }
}
