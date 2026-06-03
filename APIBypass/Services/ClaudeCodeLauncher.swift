import Foundation
import AppKit

/// 终端应用配置
struct TerminalApp: Identifiable, Equatable {
    let id: String
    let name: String
    let bundleId: String?
    let path: String?
    let launchCommand: (String, [String: String], String?) -> String
    let launchWindowCommand: ((String, [String: String], String?) -> String)?
    let launchTabCommand: ((String, [String: String], String?) -> String)?

    static func == (lhs: TerminalApp, rhs: TerminalApp) -> Bool {
        lhs.id == rhs.id
    }
}

/// 模型配置模板 — 保存一组模型参数配置
struct LaunchTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var anthropicModel: String
    var anthropicModelProviderId: String?
    var opusModel: String
    var opusModelProviderId: String?
    var sonnetModel: String
    var sonnetModelProviderId: String?
    var haikuModel: String
    var haikuModelProviderId: String?
    var subagentModel: String
    var subagentModelProviderId: String?
    var effortLevel: String?
    var disableAttributionHeader: Bool?
    var rectifierEnabled: Bool?

    init(
        id: UUID = UUID(),
        name: String,
        anthropicModel: String = "",
        anthropicModelProviderId: String? = nil,
        opusModel: String = "",
        opusModelProviderId: String? = nil,
        sonnetModel: String = "",
        sonnetModelProviderId: String? = nil,
        haikuModel: String = "",
        haikuModelProviderId: String? = nil,
        subagentModel: String = "",
        subagentModelProviderId: String? = nil,
        effortLevel: String? = nil,
        disableAttributionHeader: Bool? = nil,
        rectifierEnabled: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.anthropicModel = anthropicModel
        self.anthropicModelProviderId = anthropicModelProviderId
        self.opusModel = opusModel
        self.opusModelProviderId = opusModelProviderId
        self.sonnetModel = sonnetModel
        self.sonnetModelProviderId = sonnetModelProviderId
        self.haikuModel = haikuModel
        self.haikuModelProviderId = haikuModelProviderId
        self.subagentModel = subagentModel
        self.subagentModelProviderId = subagentModelProviderId
        self.effortLevel = effortLevel
        self.disableAttributionHeader = disableAttributionHeader
        self.rectifierEnabled = rectifierEnabled
    }
}

/// 终端启动模式
enum TerminalLaunchMode: String, Codable {
    case newWindow
    case newTab
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
    let launchMode: TerminalLaunchMode
}

/// Claude Code 启动器
final class ClaudeCodeLauncher {

    // MARK: - Template Persistence

    private static let templatesKey = "launcher.templates"
    private static let recentDirectoriesKey = "launcher.recentDirectories"

    static func defaultTemplates() -> [LaunchTemplate] {
        [
            LaunchTemplate(
                name: "Default",
                anthropicModel: "",
                opusModel: "",
                sonnetModel: "",
                haikuModel: "",
                subagentModel: "",
                effortLevel: "",
                disableAttributionHeader: false,
                rectifierEnabled: true
            ),
        ]
    }

    static func loadTemplates() -> [LaunchTemplate] {
        guard let data = UserDefaults.standard.data(forKey: templatesKey) else {
            return defaultTemplates()
        }
        guard let decoded = try? JSONDecoder().decode([LaunchTemplate].self, from: data) else {
            return defaultTemplates()
        }
        return decoded
    }

    static func saveTemplates(_ templates: [LaunchTemplate]) {
        if let data = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(data, forKey: templatesKey)
        }
    }

    static func loadRecentDirectories() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: recentDirectoriesKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    static func saveRecentDirectories(_ dirs: [String]) {
        if let data = try? JSONEncoder().encode(dirs) {
            UserDefaults.standard.set(data, forKey: recentDirectoriesKey)
        }
    }

    static func addRecentDirectory(_ path: String) {
        var dirs = loadRecentDirectories()
        dirs.removeAll { $0 == path }
        dirs.insert(path, at: 0)
        if dirs.count > 5 { dirs = Array(dirs.prefix(5)) }
        saveRecentDirectories(dirs)
    }

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
                },
                launchWindowCommand: { claudePath, envVars, workDir in
                    let envExports = envVars.map { "export \($0.key)='\($0.value)'" }.joined(separator: " && ")
                    let cdCommand = workDir != nil ? "cd '\(workDir!)' && " : ""
                    return "tell application \"Terminal\"\nactivate\ndo script \"\(cdCommand)\(envExports) && \(claudePath)\"\nend tell"
                },
                launchTabCommand: { claudePath, envVars, workDir in
                    let envExports = envVars.map { "export \($0.key)='\($0.value)'" }.joined(separator: " && ")
                    let cdCommand = workDir != nil ? "cd '\(workDir!)' && " : ""
                    return "tell application \"Terminal\"\nactivate\ntell application \"System Events\" to keystroke \"t\" using command down\ndo script \"\(cdCommand)\(envExports) && \(claudePath)\" in front window\nend tell"
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
                        return "tell application \"iTerm\"\nactivate\ncreate window with default profile\ntell current session of current window\nwrite text \"\(cdCommand)\(envExports) && \(claudePath)\"\nend tell\nend tell"
                    },
                    launchWindowCommand: { claudePath, envVars, workDir in
                        let envExports = envVars.map { "export \($0.key)='\($0.value)'" }.joined(separator: " && ")
                        let cdCommand = workDir != nil ? "cd '\(workDir!)' && " : ""
                        return "tell application \"iTerm\"\nactivate\ncreate window with default profile\ntell current session of current window\nwrite text \"\(cdCommand)\(envExports) && \(claudePath)\"\nend tell\nend tell"
                    },
                    launchTabCommand: { claudePath, envVars, workDir in
                        let envExports = envVars.map { "export \($0.key)='\($0.value)'" }.joined(separator: " && ")
                        let cdCommand = workDir != nil ? "cd '\(workDir!)' && " : ""
                        return "tell application \"iTerm\"\nactivate\ntell current window\ncreate tab with default profile\ntell current session\nwrite text \"\(cdCommand)\(envExports) && \(claudePath)\"\nend tell\nend tell\nend tell"
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
                    },
                    launchWindowCommand: nil,
                    launchTabCommand: nil
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
                    },
                    launchWindowCommand: nil,
                    launchTabCommand: nil
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
                },
                launchWindowCommand: nil,
                launchTabCommand: nil
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
                },
                launchWindowCommand: nil,
                launchTabCommand: nil
            ))
        }

        return terminals
    }

    /// 检测指定终端是否已有实例在运行
    static func isTerminalRunning(_ terminal: TerminalApp) -> Bool {
        guard let bundleId = terminal.bundleId else { return false }
        return !NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleId
        ).isEmpty
    }

    /// 检测终端是否有可见窗口（通过 CGWindowList 避免 AppleScript 调用）
    static func hasVisibleWindow(_ terminal: TerminalApp) -> Bool {
        guard let bundleId = terminal.bundleId else { return false }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return false }

        let pid = app.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for window in windowList {
            if let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid {
                // 确保是应用窗口（非菜单栏图标等 layer < 0 的元素）
                if let layer = window[kCGWindowLayer as String] as? Int32, layer >= 0 {
                    return true
                }
            }
        }
        return false
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

        // 根据 launchMode 选择对应的命令闭包
        let command: String
        switch configuration.launchMode {
        case .newTab:
            if let tabCmd = terminal.launchTabCommand {
                command = tabCmd(claudePath, envVars, workDir)
            } else {
                command = terminal.launchCommand(claudePath, envVars, workDir)
            }
        case .newWindow:
            if let windowCmd = terminal.launchWindowCommand {
                command = windowCmd(claudePath, envVars, workDir)
            } else {
                command = terminal.launchCommand(claudePath, envVars, workDir)
            }
        }

        let script = command

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
