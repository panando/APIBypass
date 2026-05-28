import Foundation

/// Claude Code 启动器错误
enum LauncherError: Error, LocalizedError {
    case claudeCodeNotFound
    case launchFailed(String)
    case keychainReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .claudeCodeNotFound:
            return L10n.t("launcher_claude_not_found")
        case .launchFailed(let message):
            return L10n.t("launcher_failed", message)
        case .keychainReadFailed(let message):
            return L10n.t("launcher_keychain_failed", message)
        }
    }
}

/// Claude Code 启动配置
struct LaunchConfiguration {
    let provider: ProviderConfig
    let selectedMapping: ModelMapping?
    let customEnvVars: [String: String]
}

/// Claude Code 启动器
final class ClaudeCodeLauncher {

    // MARK: - 环境变量构建

    /// 构建环境变量字典
    /// - Parameters:
    ///   - provider: 提供商配置
    ///   - selectedMapping: 选中的模型映射（可选）
    ///   - customEnvVars: 自定义环境变量（覆盖配置中的值）
    /// - Returns: 完整的环境变量字典
    func buildEnvironmentVariables(
        provider: ProviderConfig,
        selectedMapping: ModelMapping? = nil,
        customEnvVars: [String: String] = [:]
    ) -> [String: String] {
        var env: [String: String] = [:]

        // 合并系统环境变量
        for (key, value) in ProcessInfo.processInfo.environment {
            env[key] = value
        }

        // 处理 Provider 配置的环境变量
        for varConfig in provider.environmentVariables where varConfig.isEnabled {
            // 如果自定义环境变量中有相同 key，使用自定义值
            if let customValue = customEnvVars[varConfig.name] {
                env[varConfig.name] = customValue
                continue
            }

            let value: String

            switch varConfig.type {
            case .manual:
                value = varConfig.value

            case .baseURL:
                value = provider.baseURL.absoluteString

            case .modelMapping:
                value = selectedMapping?.incomingModel ?? varConfig.value
                if value.isEmpty {
                    // 如果没有选中映射且没有默认值，使用第一个启用的映射
                    continue
                }

            case .keychainToken:
                // 从 Keychain 读取 API Key
                do {
                    if let token = try KeychainService.shared.retrieve(forKey: provider.id.uuidString) {
                        value = token
                    } else {
                        // Keychain 中没有找到，跳过这个环境变量
                        continue
                    }
                } catch {
                    // 读取失败，跳过
                    continue
                }
            }

            env[varConfig.name] = value
        }

        // 最后合并所有自定义环境变量（覆盖 Provider 配置中的值）
        for (key, value) in customEnvVars {
            env[key] = value
        }

        return env
    }

    // MARK: - Claude Code 启动

    /// 启动 Claude Code
    /// - Parameters:
    ///   - configuration: 启动配置
    ///   - workingDirectory: 工作目录（可选，默认为当前目录）
    /// - Returns: 启动的进程
    /// - Throws: LauncherError
    func launchClaudeCode(
        configuration: LaunchConfiguration,
        workingDirectory: URL? = nil
    ) throws -> Process {
        let process = Process()

        // 查找 Claude Code 可执行文件
        guard let claudePath = findClaudeCodeExecutable() else {
            throw LauncherError.claudeCodeNotFound
        }

        process.executableURL = URL(fileURLWithPath: claudePath)

        // 构建环境变量
        let env = buildEnvironmentVariables(
            provider: configuration.provider,
            selectedMapping: configuration.selectedMapping,
            customEnvVars: configuration.customEnvVars
        )
        process.environment = env

        // 设置工作目录
        if let workingDir = workingDirectory {
            process.currentDirectoryURL = workingDir
        } else {
            process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        }

        // 设置输出管道
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // 启动进程
        try process.run()

        return process
    }

    // MARK: - 查找可执行文件

    /// 查找 Claude Code 可执行文件路径
    /// - Returns: 可执行文件路径，如果未找到则返回 nil
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
        let nvmGlobPattern = "\(homeDirectory)/.nvm/versions/node/*/bin/claude"
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
}
