import Foundation

/// 终端应用配置
struct TerminalApp: Identifiable, Equatable {
    let id: String
    let name: String
    let bundleId: String?
    let path: String?
    let launchCommand: (String, [String: String], String?) -> String

    static func == (lhs: TerminalApp, rhs: TerminalApp) -> Bool {
        lhs.id == rhs.id
    }
}

/// Claude Code 启动器错误
enum LauncherError: Error, LocalizedError {
    case claudeCodeNotFound
    case terminalNotFound
    case launchFailed(String)
    case keychainReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .claudeCodeNotFound:
            return L10n.t("launcher_claude_not_found")
        case .terminalNotFound:
            return L10n.t("launcher_terminal_not_found")
        case .launchFailed(let message):
            return "\(L10n.t("launcher_failed")): \(message)"
        case .keychainReadFailed(let message):
            return "\(L10n.t("launcher_keychain_failed")): \(message)"
        }
    }
}

/// Claude Code 启动配置
struct LaunchConfiguration {
    let provider: ProviderConfig
    let selectedMapping: ModelMapping?
    let customEnvVars: [String: String]
    let workingDirectory: URL?
    let disableAttributionHeader: Bool
}

/// Claude Code 启动器
final class ClaudeCodeLauncher {

    // MARK: - 1M context detection

    /// Known 1M context window models (matched by regex, case-insensitive).
    /// Claude Code CLI parses `[1m]` suffix to budget /context for 1e6 tokens,
    /// then strips it before the API call.
    /// Sources: DeepSeek & MiMo official Claude Code integration docs.
    private static let deepseek1MPattern = #"(?i)(\w+-)?deepseek-v([4-9]|\d{2,})([.-]\w+)*"#
    private static let mimo1MPattern   = #"(?i)(\w+-)?mimo-v(2\.[5-9]|2\.\d{2,}|[3-9]|\d{2,})([.-]\w+)*"#

    /// Append `[1m]` suffix if the model supports a 1M context window.
    static func with1MContextSuffix(_ model: String) -> String {
        if model.range(of: #"\[1m\]"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return model
        }
        if model.range(of: deepseek1MPattern, options: .regularExpression) != nil ||
           model.range(of: mimo1MPattern, options: .regularExpression) != nil {
            return "\(model)[1m]"
        }
        return model
    }

    // MARK: - 终端检测

    /// 获取系统可用的终端应用列表
    static func availableTerminals() -> [TerminalApp] {
        var terminals: [TerminalApp] = []

        // Terminal.app (系统自带)
        let terminalPath = "/System/Applications/Utilities/Terminal.app"
        if FileManager.default.fileExists(atPath: terminalPath) {
            terminals.append(TerminalApp(
                id: "terminal",
                name: "Terminal",
                bundleId: "com.apple.Terminal",
                path: terminalPath,
                launchCommand: { claudePath, envVars, workDir in
                    let envExports = envVars.map { "export \($0.key)='\($0.value)'" }.joined(separator: " && ")
                    let cdCommand = workDir != nil ? "cd '\(workDir!)' && " : ""
                    return "tell application \"Terminal\"\nactivate\ndo script \"\(cdCommand)\(envExports) && \(claudePath)\"\nend tell"
                }
            ))
        }

        // iTerm2
        let itermPaths = [
            "/Applications/iTerm.app",
            NSHomeDirectory() + "/Applications/iTerm.app"
        ]
        for path in itermPaths {
            if FileManager.default.fileExists(atPath: path) {
                terminals.append(TerminalApp(
                    id: "iterm2",
                    name: "iTerm2",
                    bundleId: "com.googlecode.iterm2",
                    path: path,
                    launchCommand: { claudePath, envVars, workDir in
                        let envExports = envVars.map { "export \($0.key)='\($0.value)'" }.joined(separator: " && ")
                        let cdCommand = workDir != nil ? "cd '\(workDir!)' && " : ""
                        return "tell application \"iTerm2\"\nactivate\ncreate window with default profile\ntell current session of current window\nwrite text \"\(cdCommand)\(envExports) && \(claudePath)\"\nend tell\nend tell"
                    }
                ))
                break
            }
        }

        // Alacritty
        let alacrittyPaths = [
            "/Applications/Alacritty.app",
            NSHomeDirectory() + "/Applications/Alacritty.app"
        ]
        for path in alacrittyPaths {
            if FileManager.default.fileExists(atPath: path) {
                terminals.append(TerminalApp(
                    id: "alacritty",
                    name: "Alacritty",
                    bundleId: "io.alacritty",
                    path: path,
                    launchCommand: { claudePath, envVars, workDir in
                        let envString = envVars.map { "\($0.key)=\'\($0.value)\'" }.joined(separator: " ")
                        let cdCommand = workDir != nil ? "cd '\(workDir!)' && " : ""
                        return "tell application \"Alacritty\" to activate\ndo shell script \"\(envString) \(cdCommand)\(claudePath) &\""
                    }
                ))
                break
            }
        }

        // Kitty
        let kittyPaths = [
            "/Applications/kitty.app",
            NSHomeDirectory() + "/Applications/kitty.app"
        ]
        for path in kittyPaths {
            if FileManager.default.fileExists(atPath: path) {
                terminals.append(TerminalApp(
                    id: "kitty",
                    name: "Kitty",
                    bundleId: "net.kovidgoyal.kitty",
                    path: path,
                    launchCommand: { claudePath, envVars, workDir in
                        let envExports = envVars.map { "export \($0.key)='\($0.value)'" }.joined(separator: " && ")
                        let cdCommand = workDir != nil ? "cd '\(workDir!)' && " : ""
                        return "tell application \"kitty\"\nactivate\nend tell\ndo shell script \"\(cdCommand)\(envExports) && \(claudePath) &\""
                    }
                ))
                break
            }
        }

        // Warp
        let warpPath = "/Applications/Warp.app"
        if FileManager.default.fileExists(atPath: warpPath) {
            terminals.append(TerminalApp(
                id: "warp",
                name: "Warp",
                bundleId: "dev.warp.Warp-Stable",
                path: warpPath,
                launchCommand: { claudePath, envVars, workDir in
                    let envExports = envVars.map { "export \($0.key)='\($0.value)'" }.joined(separator: " && ")
                    let cdCommand = workDir != nil ? "cd '\(workDir!)' && " : ""
                    return "tell application \"Warp\" to activate\ndo shell script \"\(cdCommand)\(envExports) && \(claudePath) &\""
                }
            ))
        }

        // Hyper
        let hyperPath = "/Applications/Hyper.app"
        if FileManager.default.fileExists(atPath: hyperPath) {
            terminals.append(TerminalApp(
                id: "hyper",
                name: "Hyper",
                bundleId: "co.zeit.hyper",
                path: hyperPath,
                launchCommand: { claudePath, envVars, workDir in
                    let envExports = envVars.map { "export \($0.key)='\($0.value)'" }.joined(separator: " && ")
                    let cdCommand = workDir != nil ? "cd '\(workDir!)' && " : ""
                    return "tell application \"Hyper\" to activate\ndo shell script \"\(cdCommand)\(envExports) && \(claudePath) &\""
                }
            ))
        }

        return terminals
    }

    // MARK: - Claude Code 查找

    /// 查找 Claude Code 可执行文件路径
    func findClaudeCodeExecutable() -> String? {
        // 1. 尝试从 PATH 查找
        if let pathFromWhich = findClaudeUsingWhich() {
            return pathFromWhich
        }

        // 2. 检查常见安装位置
        if let pathFromCommon = findClaudeInCommonLocations() {
            return pathFromCommon
        }

        return nil
    }

    /// 使用 `which` 命令查找
    private func findClaudeUsingWhich() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["claude"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                return path
            }
        } catch {
            // 忽略错误，继续尝试其他方法
        }

        return nil
    }

    /// 在常见安装位置查找
    private func findClaudeInCommonLocations() -> String? {
        let homeDirectory = NSHomeDirectory()

        let commonPaths = [
            "\(homeDirectory)/.local/bin/claude",
            "\(homeDirectory)/.nvm/versions/node/v18.20.4/bin/claude",
            "\(homeDirectory)/.nvm/versions/node/v20.12.2/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/bin/claude"
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // 尝试匹配 nvm 版本通配符
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: "\(homeDirectory)/.nvm/versions/node")
            for version in files {
                let path = "\(homeDirectory)/.nvm/versions/node/\(version)/bin/claude"
                if FileManager.default.fileExists(atPath: path) {
                    return path
                }
            }
        } catch {
            // 忽略错误
        }

        return nil
    }

    // MARK: - 启动

    /// 在指定终端中启动 Claude Code
    /// - Parameters:
    ///   - terminal: 终端应用
    ///   - configuration: 启动配置
    /// - Throws: LauncherError
    func launchInTerminal(terminal: TerminalApp, configuration: LaunchConfiguration) throws {
        // 查找 Claude Code 可执行文件
        guard let claudePath = findClaudeCodeExecutable() else {
            throw LauncherError.claudeCodeNotFound
        }

        // 构建环境变量
        var envVars = configuration.customEnvVars

        // 使用传入的环境变量
        for (key, value) in configuration.customEnvVars {
            envVars[key] = value
        }

        // cch Solution 2: 禁用动态归因 header，避免破坏 prompt 前缀缓存
        if configuration.disableAttributionHeader {
            envVars["CLAUDE_CODE_ATTRIBUTION_HEADER"] = "0"
        }

        // 工作目录
        let workDir = configuration.workingDirectory?.path

        // 生成 AppleScript 命令
        let script = terminal.launchCommand(claudePath, envVars, workDir)

        // 执行 AppleScript
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        do {
            try task.run()
        } catch {
            throw LauncherError.launchFailed(error.localizedDescription)
        }
    }
}
