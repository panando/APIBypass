import Foundation
import AppKit

// MARK: - FileSystem Abstraction

/// Abstract file system operations for testability
protocol FileSystem {
    func fileExists(atPath path: String) -> Bool
    func contentsOfDirectory(atPath path: String) throws -> [String]
}

/// Production file system backed by FileManager.default
struct DefaultFileSystem: FileSystem {
    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }
}

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
    case accessibilityDenied

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
        case .accessibilityDenied:
            return L10n.t("launcher_accessibility_denied")
        }
    }

    var isAccessibilityError: Bool {
        if case .accessibilityDenied = self { return true }
        return false
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

        // Warp / Warple
        let warpPaths = [
            "/Applications/Warp.app",
            NSHomeDirectory() + "/Applications/Warp.app",
            "/Applications/Warple.app",
            NSHomeDirectory() + "/Applications/Warple.app"
        ]
        for path in warpPaths {
            if FileManager.default.fileExists(atPath: path) {
                let appName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                let plistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
                let bundleId = (try? String(contentsOf: URL(fileURLWithPath: plistPath), encoding: .utf8))
                    .flatMap { plist in
                        let pattern = #"<key>CFBundleIdentifier</key>\s*<string>([^<]+)</string>"#
                        return try? NSRegularExpression(pattern: pattern)
                            .firstMatch(in: plist, range: NSRange(plist.startIndex..., in: plist))
                            .flatMap { Range($0.range(at: 1), in: plist) }
                            .map { String(plist[$0]) }
                    }
                terminals.append(TerminalApp(
                    id: appName.lowercased(),
                    name: appName,
                    bundleId: bundleId,
                    path: path,
                    launchCommand: { _, _, _ in "" },
                    launchWindowCommand: nil,
                    launchTabCommand: nil
                ))
                break
            }
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
        // 1. 检查常见安装位置（快速，无需启动进程）
        if let path = Self.findClaudeInCommonLocations(fs: DefaultFileSystem(), home: NSHomeDirectory()) {
            return path
        }

        // 2. 通过登录 shell PATH 查找（较慢但全面，覆盖所有安装方式）
        if let path = findClaudeUsingWhich() {
            return path
        }

        return nil
    }

    /// 使用登录 shell 的 `which` 查找（继承用户完整 PATH，覆盖 nvm/fnm/volta 等）
    private func findClaudeUsingWhich() -> String? {
        let shells = ["/bin/zsh", "/bin/bash"]
        for shell in shells {
            guard FileManager.default.fileExists(atPath: shell) else { continue }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: shell)
            task.arguments = ["-l", "-c", "which claude"]

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
                // 忽略错误，尝试下一个 shell
            }
        }

        return nil
    }

    /// 在常见安装位置查找，覆盖所有官方安装方式
    static func findClaudeInCommonLocations(fs: FileSystem, home: String) -> String? {
        // 固定路径，按安装方式分组
        let commonPaths = [
            // Native install: curl -fsSL https://claude.ai/install.sh | bash
            "\(home)/.local/bin/claude",

            // Auto-updater / desktop app CLI
            "\(home)/.claude/bin/claude",

            // Homebrew (Apple Silicon / Intel)
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",

            // Volta: npm via volta shim
            "\(home)/.volta/bin/claude",

            // System
            "/usr/bin/claude"
        ]

        for path in commonPaths {
            if fs.fileExists(atPath: path) {
                return path
            }
        }

        // npm + nvm: 动态扫描所有已安装的 node 版本
        if let path = findInVersionDirectory("\(home)/.nvm/versions/node", binary: "claude", fs: fs) {
            return path
        }

        // npm + fnm (macOS / Linux 路径)
        let fnmPaths = [
            "\(home)/Library/Application Support/fnm/node-versions",
            "\(home)/.local/share/fnm/node-versions"
        ]
        for fnmPath in fnmPaths {
            if let path = findInVersionDirectory(fnmPath, binary: "claude", fs: fs) {
                return path
            }
        }

        // Homebrew cask: brew install --cask claude-code → 在 .app 内搜索 CLI 二进制
        if let path = findClaudeInAppBundle(fs: fs, home: home) {
            return path
        }

        return nil
    }

    /// 在版本管理器的 node 版本目录中查找可执行文件
    static func findInVersionDirectory(_ dir: String, binary: String, fs: FileSystem) -> String? {
        do {
            let versions = try fs.contentsOfDirectory(atPath: dir)
            for version in versions.sorted().reversed() {
                // 标准结构: <version>/bin/<binary>
                let path = "\(dir)/\(version)/bin/\(binary)"
                if fs.fileExists(atPath: path) {
                    return path
                }
                // fnm 结构: <version>/installation/bin/<binary>
                let installPath = "\(dir)/\(version)/installation/bin/\(binary)"
                if fs.fileExists(atPath: installPath) {
                    return installPath
                }
            }
        } catch {
            // 目录不存在，忽略
        }
        return nil
    }

    /// 在 Claude.app 内部搜索 CLI 可执行文件（Homebrew cask 安装方式）
    static func findClaudeInAppBundle(fs: FileSystem, home: String) -> String? {
        let appPaths = [
            "/Applications/Claude.app",
            "/Applications/Claude Code.app",
            "\(home)/Applications/Claude.app",
            "\(home)/Applications/Claude Code.app"
        ]

        for appPath in appPaths {
            let macOSDir = (appPath as NSString).appendingPathComponent("Contents/MacOS")
            do {
                let files = try fs.contentsOfDirectory(atPath: macOSDir)
                // 查找名为 claude 的可执行文件（忽略大小写）
                if let found = files.first(where: { $0.lowercased() == "claude" }) {
                    return (macOSDir as NSString).appendingPathComponent(found)
                }
            } catch {
                // 目录不存在，忽略
            }
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

        // Warp/Warple 特殊处理：在工作目录写临时脚本 + open -a 打开（无需辅助功能权限）
        if terminal.id == "warp" || terminal.id == "warple" {
            let appName = terminal.name

            // 构建启动脚本内容
            let envExports = envVars.map { "export \($0.key)='\($0.value)'" }.joined(separator: "\n")
            // 脚本写到工作目录，这样 Warple 打开时终端自然就在正确目录
            // 脚本执行时 rm -- "$0" 自删除
            let scriptContent = "#!/bin/bash\nrm -- \"$0\"\n\(envExports)\nexec \(claudePath)"

            let scriptDir = workDir ?? NSHomeDirectory()
            let scriptPath = (scriptDir as NSString).appendingPathComponent(".apibypass_launch.sh")
            try? scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

            // open -a Warple script.sh — 在终端中打开并执行脚本
            let openTask = Process()
            openTask.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            openTask.arguments = ["-a", appName, scriptPath]
            do {
                try openTask.run()
                openTask.waitUntilExit()
            } catch {
                throw LauncherError.launchFailed(error.localizedDescription)
            }

            return
        }

        // 先检测辅助功能权限（快速探测，不等主脚本完成）
        let needsKeystroke = script.contains("keystroke") || script.contains("key code")
        if needsKeystroke {
            let checkTask = Process()
            checkTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            checkTask.arguments = ["-e", "tell application \"System Events\" to get name of first process"]
            let checkPipe = Pipe()
            checkTask.standardError = checkPipe
            checkTask.standardOutput = Pipe()
            try checkTask.run()
            checkTask.waitUntilExit()
            if checkTask.terminationStatus != 0 {
                let errData = checkPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                if errStr.contains("不允许发送按键") || errStr.contains("not allowed to send keystrokes") || errStr.contains("1002") {
                    throw LauncherError.accessibilityDenied
                }
            }
        }

        // 执行 AppleScript（fire-and-forget，不阻塞等待）
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
