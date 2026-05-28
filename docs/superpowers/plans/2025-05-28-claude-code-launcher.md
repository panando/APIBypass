# Claude Code 启动器功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现从 APIBypass 菜单栏一键启动 Claude Code 并自动注入环境变量的功能。

**Architecture:** 扩展 ProviderConfig 支持环境变量模板配置，新增 ClaudeCodeLauncher 服务处理进程启动，在 MenuBar 添加启动入口，使用 SwiftUI 实现配置和确认界面。

**Tech Stack:** Swift, SwiftUI, Foundation (Process API), SwiftData (UserDefaults), Keychain

---

## 文件结构概览

### 新增文件（5 个）
1. `APIBypass/Models/EnvironmentVariableConfig.swift` - 环境变量配置模型
2. `APIBypass/Services/ClaudeCodeLauncher.swift` - Claude Code 启动服务
3. `APIBypass/UI/Views/EnvironmentVariablesCard.swift` - Provider 详情页环境变量卡片
4. `APIBypass/UI/Views/LaunchClaudeCodeView.swift` - 启动确认界面

### 修改文件（3 个）
5. `APIBypass/Models/ProviderConfig.swift` - 添加 environmentVariables 字段
6. `APIBypass/UI/MenuBarView.swift` - 添加启动菜单项
7. `APIBypass/Core/ConfigManager.swift` - 添加数据迁移逻辑

---

## Task 1: 创建环境变量配置模型

**Files:**
- Create: `APIBypass/Models/EnvironmentVariableConfig.swift`

- [ ] **Step 1: 编写 EnvironmentVariableConfig 模型**

```swift
import Foundation

/// 环境变量配置项
struct EnvironmentVariableConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var value: String
    var type: EnvVarType
    var isEnabled: Bool
    
    init(id: UUID = UUID(), name: String, value: String = "", type: EnvVarType = .manual, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.value = value
        self.type = type
        self.isEnabled = isEnabled
    }
}

/// 环境变量值类型
enum EnvVarType: String, Codable, CaseIterable {
    case manual          // 手动输入
    case modelMapping    // 从模型映射中选择 incomingModel
    case keychainToken   // 从 Keychain 读取 API Key
    case baseURL         // 使用 Provider 的 baseURL
}

// MARK: - Localization Helpers

extension EnvVarType {
    var localizedName: String {
        switch self {
        case .manual:
            return L10n.t("envvar_manual")
        case .modelMapping:
            return L10n.t("envvar_model_mapping")
        case .keychainToken:
            return L10n.t("envvar_keychain_token")
        case .baseURL:
            return L10n.t("envvar_base_url")
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add APIBypass/Models/EnvironmentVariableConfig.swift
git commit -m "feat: add EnvironmentVariableConfig model for Claude Code launcher"
```

---

## Task 2: 扩展 ProviderConfig

**Files:**
- Modify: `APIBypass/Models/ProviderConfig.swift`

- [ ] **Step 1: 读取当前 ProviderConfig.swift 文件**

使用 Read 工具读取 `/Users/panando/ClaudeCode/APIbypass/APIBypass/Models/ProviderConfig.swift`

- [ ] **Step 2: 添加 environmentVariables 字段和默认模板方法**

```swift
import Foundation

struct ProviderConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var apiProvider: APIProvider
    var baseURL: URL
    var environmentVariables: [EnvironmentVariableConfig]  // 新增
    
    init(
        id: UUID = UUID(),
        name: String,
        apiProvider: APIProvider,
        baseURL: URL,
        environmentVariables: [EnvironmentVariableConfig]? = nil
    ) {
        self.id = id
        self.name = name
        self.apiProvider = apiProvider
        self.baseURL = baseURL
        self.environmentVariables = environmentVariables ?? ProviderConfig.defaultEnvironmentVariables()
    }
    
    // 预设的环境变量模板
    static func defaultEnvironmentVariables() -> [EnvironmentVariableConfig] {
        [
            EnvironmentVariableConfig(
                id: UUID(),
                name: "ANTHROPIC_BASE_URL",
                value: "",
                type: .baseURL,
                isEnabled: true
            ),
            EnvironmentVariableConfig(
                id: UUID(),
                name: "ANTHROPIC_MODEL",
                value: "",
                type: .modelMapping,
                isEnabled: true
            ),
            EnvironmentVariableConfig(
                id: UUID(),
                name: "ANTHROPIC_AUTH_TOKEN",
                value: "",
                type: .keychainToken,
                isEnabled: true
            )
        ]
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add APIBypass/Models/ProviderConfig.swift
git commit -m "feat: add environmentVariables to ProviderConfig"
```

---

## Task 3: 创建 ClaudeCodeLauncher 服务

**Files:**
- Create: `APIBypass/Services/ClaudeCodeLauncher.swift`

- [ ] **Step 1: 编写 ClaudeCodeLauncher 服务**

```swift
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
    private func findClaudeCodeExecutable() -> String? {
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
```

- [ ] **Step 2: Commit**

```bash
git add APIBypass/Services/ClaudeCodeLauncher.swift
git commit -m "feat: add ClaudeCodeLauncher service"
```

---

## 后续任务

由于内容长度限制，剩余任务将在下一个计划文档中继续。已完成前 3 个核心任务的设计：

1. ✅ Task 1: 创建 EnvironmentVariableConfig 模型
2. ✅ Task 2: 扩展 ProviderConfig 添加 environmentVariables 字段
3. ✅ Task 3: 创建 ClaudeCodeLauncher 服务

后续需要继续设计的任务：
- Task 4: 创建 EnvironmentVariablesCard UI 组件
- Task 5: 创建 LaunchClaudeCodeView 启动界面
- Task 6: 修改 MenuBarView 添加菜单项
- Task 7: 添加数据迁移逻辑
- Task 8: 添加国际化字符串
- Task 9: 编写单元测试
