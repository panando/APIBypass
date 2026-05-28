# Claude Code 启动器功能设计文档

## 概述

为 APIBypass 增加"启动 Claude Code"功能，允许用户从菜单栏启动 Claude Code，并自动注入配置好的环境变量（包括 Provider 配置的模型映射和 Keychain 存储的 API Key）。

## 需求分析

### 用户场景

用户希望在 APIBypass 中配置好 Provider 和模型映射后，能够一键启动 Claude Code，并且：
1. 自动使用选中的 Provider 配置（Base URL、模型等）
2. 自动注入 API Key（从 Keychain 读取）
3. 可以选择使用哪个模型映射（incomingModel）

### 功能需求

1. **数据模型扩展**：在 ProviderConfig 中增加环境变量配置
2. **Keychain 集成**：使用现有 KeychainService 存储/读取 API Key
3. **UI 界面**：环境变量配置界面、启动确认界面
4. **菜单栏入口**："启动 Claude Code" 菜单项
5. **进程管理**：启动 Claude Code 进程并注入环境变量

## 设计方案

### 1. 数据模型

#### 1.1 环境变量配置项

```swift
struct EnvironmentVariableConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var value: String
    var type: EnvVarType
    var isEnabled: Bool
    
    enum EnvVarType: String, Codable {
        case manual          // 手动输入
        case modelMapping    // 从模型映射中选择 incomingModel
        case keychainToken   // 从 Keychain 读取 API Key
        case baseURL         // 使用 Provider 的 baseURL
    }
}
```

#### 1.2 ProviderConfig 扩展

```swift
struct ProviderConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var apiProvider: APIProvider
    var baseURL: URL
    var environmentVariables: [EnvironmentVariableConfig]  // 新增
    
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

### 2. 核心服务

#### 2.1 ClaudeCodeLauncher 服务

```swift
import Foundation

final class ClaudeCodeLauncher {
    
    struct LaunchConfiguration {
        let provider: ProviderConfig
        let selectedMapping: ModelMapping?
        let environmentVariables: [String: String]
    }
    
    // 构建环境变量字典
    func buildEnvironmentVariables(
        provider: ProviderConfig,
        selectedMapping: ModelMapping?,
        customVars: [EnvironmentVariableConfig]
    ) -> [String: String] {
        var env: [String: String] = [:]
        
        // 合并系统环境变量
        for (key, value) in ProcessInfo.processInfo.environment {
            env[key] = value
        }
        
        // 处理配置的环境变量
        for varConfig in customVars where varConfig.isEnabled {
            let value: String
            
            switch varConfig.type {
            case .manual:
                value = varConfig.value
                
            case .baseURL:
                value = provider.baseURL.absoluteString
                
            case .modelMapping:
                value = selectedMapping?.incomingModel ?? varConfig.value
                
            case .keychainToken:
                // 从 Keychain 读取 API Key
                if let token = try? KeychainService.shared.retrieve(forKey: provider.id.uuidString) {
                    value = token
                } else {
                    continue
                }
            }
            
            env[varConfig.name] = value
        }
        
        return env
    }
    
    // 启动 Claude Code
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
        process.environment = configuration.environmentVariables
        
        if let workingDir = workingDirectory {
            process.currentDirectoryURL = workingDir
        }
        
        // 捕获输出
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        
        return process
    }
    
    private func findClaudeCodeExecutable() -> String? {
        // 1. 尝试从 PATH 查找
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["claude"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        try? task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }
        
        // 2. 检查常见安装位置
        let commonPaths = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "\(NSHomeDirectory())/.nvm/versions/node/*/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]
        
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
}

enum LauncherError: Error, LocalizedError {
    case claudeCodeNotFound
    case launchFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .claudeCodeNotFound:
            return "未找到 Claude Code，请确保已安装并在 PATH 中"
        case .launchFailed(let message):
            return "启动失败: \(message)"
        }
    }
}
```

### 3. UI 界面设计

#### 3.1 环境变量配置界面（Provider 详情页内嵌）

```swift
struct EnvironmentVariablesCard: View {
    @Binding var provider: ProviderConfig
    @ObservedObject var configManager: ConfigManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude Code 环境变量")
                    .font(.headline)
                
                Spacer()
                
                Button("重置为默认") {
                    resetToDefaults()
                }
                .font(.caption)
            }
            
            Text("配置启动 Claude Code 时注入的环境变量")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            ForEach($provider.environmentVariables) { $envVar in
                EnvironmentVariableRow(
                    envVar: $envVar,
                    provider: provider,
                    mappings: configManager.mappingsForProvider(provider.id)
                )
            }
            
            Button("添加环境变量") {
                addEnvironmentVariable()
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func resetToDefaults() {
        provider.environmentVariables = ProviderConfig.defaultEnvironmentVariables()
    }
    
    private func addEnvironmentVariable() {
        let newVar = EnvironmentVariableConfig(
            id: UUID(),
            name: "",
            value: "",
            type: .manual,
            isEnabled: true
        )
        provider.environmentVariables.append(newVar)
    }
}

struct EnvironmentVariableRow: View {
    @Binding var envVar: EnvironmentVariableConfig
    let provider: ProviderConfig
    let mappings: [ModelMapping]
    
    var body: some View {
        HStack(spacing: 12) {
            // 启用开关
            Toggle("", isOn: $envVar.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
            
            // 变量名
            TextField("变量名", text: $envVar.name)
                .frame(width: 180)
            
            // 类型选择
            Picker("类型", selection: $envVar.type) {
                Text("手动输入").tag(EnvVarType.manual)
                Text("模型映射").tag(EnvVarType.modelMapping)
                Text("API Token").tag(EnvVarType.keychainToken)
                Text("Base URL").tag(EnvVarType.baseURL)
            }
            .frame(width: 120)
            .labelsHidden()
            
            // 根据类型显示不同的值编辑器
            valueEditor
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .opacity(envVar.isEnabled ? 1.0 : 0.5)
    }
    
    @ViewBuilder
    private var valueEditor: some View {
        switch envVar.type {
        case .manual:
            TextField("值", text: $envVar.value)
            
        case .modelMapping:
            // 从模型映射中选择 incomingModel
            Picker("选择模型", selection: $envVar.value) {
                Text("自动选择第一个").tag("")
                ForEach(mappings.filter { $0.isEnabled }, id: \.id) { mapping in
                    Text("\(mapping.incomingModel) → \(mapping.actualModel)")
                        .tag(mapping.incomingModel)
                }
            }
            .labelsHidden()
            
        case .keychainToken:
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.secondary)
                Text("从 Keychain 读取")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
        case .baseURL:
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                Text(provider.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
```

#### 3.2 启动确认界面（菜单栏点击后弹出）

```swift
struct LaunchClaudeCodeView: View {
    @ObservedObject var configManager: ConfigManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedProviderId: UUID?
    @State private var selectedMappingId: UUID?
    @State private var customEnvVars: [String: String] = [:]
    @State private var isLaunching = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("启动 Claude Code")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            Divider()
            
            // 提供商选择
            VStack(alignment: .leading, spacing: 8) {
                Text("选择提供商")
                    .font(.headline)
                
                Picker("提供商", selection: $selectedProviderId) {
                    Text("请选择").tag(UUID?.none)
                    ForEach(configManager.providers) { provider in
                        Text(provider.name).tag(provider.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // 模型映射选择
            if let providerId = selectedProviderId {
                let mappings = configManager.mappingsForProvider(providerId)
                if !mappings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("选择模型映射")
                            .font(.headline)
                        
                        Picker("模型映射", selection: $selectedMappingId) {
                            Text("使用第一个可用映射").tag(UUID?.none)
                            ForEach(mappings.filter { $0.isEnabled }) { mapping in
                                Text("\(mapping.incomingModel) → \(mapping.actualModel)")
                                    .tag(mapping.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            
            // 环境变量预览
            if let providerId = selectedProviderId,
               let provider = configManager.findProvider(for: providerId) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("环境变量预览")
                            .font(.headline)
                        Spacer()
                        Button("编辑") {
                            // 打开环境变量编辑器
                        }
                        .font(.caption)
                    }
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(provider.environmentVariables.filter { $0.isEnabled }) { envVar in
                                HStack {
                                    Text("\(envVar.name)=")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(previewValue(for: envVar))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
            }
            
            // 错误提示
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Spacer()
            
            // 按钮
            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("启动") {
                    launchClaudeCode()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(selectedProviderId == nil || isLaunching)
            }
        }
        .padding()
        .frame(width: 500, height: 600)
    }
    
    private func previewValue(for envVar: EnvironmentVariableConfig) -> String {
        switch envVar.type {
        case .manual:
            return envVar.value.isEmpty ? "(空)" : envVar.value
        case .baseURL:
            guard let providerId = selectedProviderId,
                  let provider = configManager.findProvider(for: providerId) else {
                return "(Provider Base URL)"
            }
            return provider.baseURL.absoluteString
        case .modelMapping:
            guard let mappingId = selectedMappingId ?? firstEnabledMappingId(),
                  let mapping = configManager.mappings.first(where: { $0.id == mappingId }) else {
                return "(模型映射)"
            }
            return mapping.incomingModel
        case .keychainToken:
            return "(从 Keychain 读取)"
        }
    }
    
    private func firstEnabledMappingId() -> UUID? {
        guard let providerId = selectedProviderId else { return nil }
        return configManager.mappingsForProvider(providerId).first { $0.isEnabled }?.id
    }
    
    private func launchClaudeCode() {
        guard let providerId = selectedProviderId,
              let provider = configManager.findProvider(for: providerId) else {
            errorMessage = "未选择提供商"
            return
        }
        
        isLaunching = true
        errorMessage = nil
        
        // 使用 launcher 启动
        let launcher = ClaudeCodeLauncher()
        let configuration = ClaudeCodeLauncher.LaunchConfiguration(
            provider: provider,
            selectedMapping: selectedMappingId.flatMap { id in
                configManager.mappings.first { $0.id == id }
            },
            environmentVariables: customEnvVars
        )
        
        do {
            let process = try launcher.launchClaudeCode(configuration: configuration)
            
            // 监听进程状态
            process.terminationHandler = { [weak self] process in
                DispatchQueue.main.async {
                    self?.isLaunching = false
                    if process.terminationStatus != 0 {
                        self?.errorMessage = "Claude Code 已退出，退出码: \(process.terminationStatus)"
                    } else {
                        self?.dismiss()
                    }
                }
            }
            
            // 成功启动后关闭窗口
            dismiss()
            
        } catch {
            isLaunching = false
            errorMessage = error.localizedDescription
        }
    }
}
```

#### 3.3 菜单栏集成

```swift
// 在 MenuBarView 中添加
Button("启动 Claude Code") {
    openLaunchClaudeCodeWindow()
}
.disabled(configManager.providers.isEmpty)

private func openLaunchClaudeCodeWindow() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    
    if let existingWindow = NSApplication.shared.windows.first(where: { 
        $0.identifier?.rawValue == "launch-claude-window" 
    }) {
        existingWindow.makeKeyAndOrderFront(nil)
        return
    }
    
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "启动 Claude Code"
    window.identifier = NSUserInterfaceItemIdentifier("launch-claude-window")
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: 
        LaunchClaudeCodeView(configManager: configManager)
    )
    window.center()
    window.makeKeyAndOrderFront(nil)
}
```

### 4. 数据迁移

为现有的 ProviderConfig 添加默认值：

```swift
// 在 ConfigManager 中添加迁移逻辑
private func migrateProviderEnvironmentVariables() {
    var needsSave = false
    
    for index in providers.indices {
        if providers[index].environmentVariables.isEmpty {
            providers[index].environmentVariables = ProviderConfig.defaultEnvironmentVariables()
            needsSave = true
        }
    }
    
    if needsSave {
        saveProviders()
    }
}
```

## 国际化

新增 i18n 键：

```swift
"launch_claude_code" = "启动 Claude Code"
"claude_code_launcher_title" = "启动 Claude Code"
"select_provider" = "选择提供商"
"select_model_mapping" = "选择模型映射"
"environment_variables_preview" = "环境变量预览"
"use_first_mapping" = "使用第一个可用映射"
"launch" = "启动"
"envvar_manual" = "手动输入"
"envvar_model_mapping" = "模型映射"
"envvar_keychain_token" = "API Token"
"envvar_base_url" = "Base URL"
```

## 文件变更清单

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `Models/ProviderConfig.swift` | 修改 | 添加 `environmentVariables` 字段和默认模板 |
| `Models/EnvironmentVariableConfig.swift` | 新增 | 环境变量配置模型 |
| `Services/ClaudeCodeLauncher.swift` | 新增 | Claude Code 启动服务 |
| `UI/Views/EnvironmentVariablesCard.swift` | 新增 | Provider 详情页的环境变量配置卡片 |
| `UI/Views/LaunchClaudeCodeView.swift` | 新增 | 启动 Claude Code 的确认界面 |
| `UI/MenuBarView.swift` | 修改 | 添加"启动 Claude Code"菜单项 |
| `Core/ConfigManager.swift` | 修改 | 添加环境变量配置迁移逻辑 |
| `Core/LocalizationManager.swift` | 修改 | 添加新的 i18n 键 |

## 测试计划

1. **单元测试**
   - `ClaudeCodeLauncher.buildEnvironmentVariables()` 正确构建环境变量字典
   - `ClaudeCodeLauncher.findClaudeCodeExecutable()` 正确查找可执行文件
   - 数据迁移逻辑正确为旧 Provider 添加默认环境变量

2. **集成测试**
   - 完整流程：选择 Provider → 选择模型映射 → 启动 Claude Code → 验证环境变量注入
   - Keychain 集成：正确读取 API Key 并注入

3. **UI 测试**
   - 环境变量配置卡片正确显示和编辑
   - 启动界面正确显示预览和选项
   - 菜单栏项正确启用/禁用

## 风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| Claude Code 未安装 | 中 | 高 | 启动前检查，提供安装指引 |
| Keychain 读取失败 | 低 | 高 | 优雅降级，提示用户手动输入 |
| 环境变量冲突 | 中 | 中 | 明确覆盖规则，提供预览确认 |
| 进程管理问题 | 低 | 中 | 正确实现 terminationHandler |

## 结论

本设计通过扩展 ProviderConfig 支持环境变量配置，实现了从 APIBypass 一键启动 Claude Code 并自动注入环境变量的功能。设计遵循现有架构模式，充分利用已有的 Keychain 存储和 Provider/Mapping 配置，为用户提供无缝的 Claude Code 启动体验。
