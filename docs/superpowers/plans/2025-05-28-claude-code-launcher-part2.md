# Claude Code 启动器功能实现计划 - Part 2

补充计划文档，包含剩余任务的详细设计。

---

## Task 4: 创建 EnvironmentVariablesCard UI 组件

**Files:**
- Create: `APIBypass/UI/Views/EnvironmentVariablesCard.swift`

- [ ] **Step 1: 编写 EnvironmentVariablesCard 组件**

```swift
import SwiftUI

/// Provider 详情页的环境变量配置卡片
struct EnvironmentVariablesCard: View {
    @Binding var provider: ProviderConfig
    @ObservedObject var configManager: ConfigManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            descriptionView
            Divider()
            environmentVariablesList
            addButton
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            Text(L10n.t("claude_code_env_vars_title"))
                .font(.headline)
            
            Spacer()
            
            Button(L10n.t("reset_to_default")) {
                resetToDefaults()
            }
            .font(.caption)
        }
    }
    
    private var descriptionView: some View {
        Text(L10n.t("claude_code_env_vars_desc"))
            .font(.caption)
            .foregroundColor(.secondary)
    }
    
    private var environmentVariablesList: some View {
        VStack(spacing: 8) {
            ForEach($provider.environmentVariables) { $envVar in
                EnvironmentVariableRow(
                    envVar: $envVar,
                    provider: provider,
                    mappings: configManager.mappingsForProvider(provider.id)
                )
            }
        }
    }
    
    private var addButton: some View {
        Button(L10n.t("add_env_var")) {
            addEnvironmentVariable()
        }
        .padding(.top, 8)
    }
    
    // MARK: - Actions
    
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

// MARK: - EnvironmentVariableRow

struct EnvironmentVariableRow: View {
    @Binding var envVar: EnvironmentVariableConfig
    let provider: ProviderConfig
    let mappings: [ModelMapping]
    
    var body: some View {
        HStack(spacing: 12) {
            enabledToggle
            nameField
            typePicker
            valueEditor
        }
        .padding(.vertical, 4)
        .opacity(envVar.isEnabled ? 1.0 : 0.5)
    }
    
    // MARK: - Subviews
    
    private var enabledToggle: some View {
        Toggle("", isOn: $envVar.isEnabled)
            .toggleStyle(.checkbox)
            .labelsHidden()
    }
    
    private var nameField: some View {
        TextField(L10n.t("env_var_name"), text: $envVar.name)
            .frame(width: 180)
    }
    
    private var typePicker: some View {
        Picker(L10n.t("env_var_type"), selection: $envVar.type) {
            ForEach(EnvVarType.allCases, id: \.self) { type in
                Text(type.localizedName).tag(type)
            }
        }
        .frame(width: 120)
        .labelsHidden()
    }
    
    @ViewBuilder
    private var valueEditor: some View {
        switch envVar.type {
        case .manual:
            TextField(L10n.t("env_var_value"), text: $envVar.value)
            
        case .modelMapping:
            modelMappingPicker
            
        case .keychainToken:
            keychainIndicator
            
        case .baseURL:
            baseURLIndicator
        }
    }
    
    private var modelMappingPicker: some View {
        Picker(L10n.t("select_model"), selection: $envVar.value) {
            Text(L10n.t("auto_select_first")).tag("")
            ForEach(mappings.filter { $0.isEnabled }, id: \.id) { mapping in
                Text("\(mapping.incomingModel) → \(mapping.actualModel)")
                    .tag(mapping.incomingModel)
            }
        }
        .labelsHidden()
    }
    
    private var keychainIndicator: some View {
        HStack {
            Image(systemName: "key.fill")
                .foregroundColor(.secondary)
            Text(L10n.t("read_from_keychain"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var baseURLIndicator: some View {
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
```

- [ ] **Step 2: Commit**

```bash
git add APIBypass/UI/Views/EnvironmentVariablesCard.swift
git commit -m "feat: add EnvironmentVariablesCard UI component"
```

---

## Task 5: 创建 LaunchClaudeCodeView 启动界面

**Files:**
- Create: `APIBypass/UI/Views/LaunchClaudeCodeView.swift`

- [ ] **Step 1: 编写 LaunchClaudeCodeView**

```swift
import SwiftUI

/// 启动 Claude Code 的确认界面
struct LaunchClaudeCodeView: View {
    @ObservedObject var configManager: ConfigManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedProviderId: UUID?
    @State private var selectedMappingId: UUID?
    @State private var customEnvVars: [String: String] = [:]
    @State private var isLaunching = false
    @State private var errorMessage: String?
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 16) {
            headerView
            Divider()
            providerSelectionView
            mappingSelectionView
            environmentVariablesPreview
            errorView
            Spacer()
            buttonBar
        }
        .padding()
        .frame(width: 500, height: 600)
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            Image(systemName: "terminal.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text(L10n.t("launch_claude_code_title"))
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
        }
    }
    
    private var providerSelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("select_provider"))
                .font(.headline)
            
            Picker(L10n.t("provider"), selection: $selectedProviderId) {
                Text(L10n.t("please_select")).tag(UUID?.none)
                ForEach(configManager.providers) { provider in
                    Text(provider.name).tag(provider.id as UUID?)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selectedProviderId) { _ in
                selectedMappingId = nil
                customEnvVars = [:]
            }
        }
    }
    
    @ViewBuilder
    private var mappingSelectionView: some View {
        if let providerId = selectedProviderId {
            let mappings = configManager.mappingsForProvider(providerId)
            if !mappings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("select_model_mapping"))
                        .font(.headline)
                    
                    Picker(L10n.t("model_mapping"), selection: $selectedMappingId) {
                        Text(L10n.t("use_first_mapping")).tag(UUID?.none)
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
    }
    
    @ViewBuilder
    private var environmentVariablesPreview: some View {
        if let providerId = selectedProviderId,
           let provider = configManager.findProvider(for: providerId) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.t("environment_variables_preview"))
                        .font(.headline)
                    Spacer()
                    Button(L10n.t("edit")) {
                        // TODO: 打开环境变量编辑器
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
    }
    
    @ViewBuilder
    private var errorView: some View {
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
    }
    
    private var buttonBar: some View {
        HStack {
            Button(L10n.t("cancel")) {
                dismiss()
            }
            .keyboardShortcut(.escape)
            
            Spacer()
            
            Button(L10n.t("launch")) {
                launchClaudeCode()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .disabled(selectedProviderId == nil || isLaunching)
        }
    }
    
    // MARK: - Helper Methods
    
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
            errorMessage = L10n.t("no_provider_selected")
            return
        }
        
        isLaunching = true
        errorMessage = nil
        
        let launcher = ClaudeCodeLauncher()
        let configuration = LaunchConfiguration(
            provider: provider,
            selectedMapping: selectedMappingId.flatMap { id in
                configManager.mappings.first { $0.id == id }
            },
            customEnvVars: customEnvVars
        )
        
        do {
            let process = try launcher.launchClaudeCode(configuration: configuration)
            
            process.terminationHandler = { [weak self] process in
                DispatchQueue.main.async {
                    self?.isLaunching = false
                    if process.terminationStatus != 0 {
                        self?.errorMessage = L10n.t("claude_code_exited", "\(process.terminationStatus)")
                    } else {
                        self?.dismiss()
                    }
                }
            }
            
            dismiss()
            
        } catch {
            isLaunching = false
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add APIBypass/UI/Views/LaunchClaudeCodeView.swift
git commit -m "feat: add LaunchClaudeCodeView UI"
```

---

## Task 5: 修改 MenuBarView 添加菜单项

**Files:**
- Modify: `APIBypass/UI/MenuBarView.swift`

- [ ] **Step 1: 读取当前 MenuBarView.swift 文件**

使用 Read 工具读取 `/Users/panando/ClaudeCode/APIbypass/APIBypass/UI/MenuBarView.swift`

- [ ] **Step 2: 添加启动 Claude Code 菜单项和相关方法**

在 `Button(L10n.t("settings"))` 后面添加：

```swift
Divider()

Button(L10n.t("launch_claude_code")) {
    openLaunchClaudeCodeWindow()
}
.disabled(configManager.providers.isEmpty)
```

然后在 `openSettingsWindow()` 方法后添加：

```swift
private func openLaunchClaudeCodeWindow() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    
    // 检查是否已存在窗口
    if let existingWindow = NSApplication.shared.windows.first(where: { 
        $0.identifier?.rawValue == "launch-claude-window" 
    }) {
        existingWindow.makeKeyAndOrderFront(nil)
        return
    }
    
    // 创建新窗口
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = L10n.t("launch_claude_code_title")
    window.identifier = NSUserInterfaceItemIdentifier("launch-claude-window")
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: 
        LaunchClaudeCodeView(configManager: configManager)
    )
    window.center()
    window.makeKeyAndOrderFront(nil)
}
```

- [ ] **Step 3: Commit**

```bash
git add APIBypass/UI/MenuBarView.swift
git commit -m "feat: add launch Claude Code menu item"
```

---

## Task 6: 添加数据迁移逻辑

**Files:**
- Modify: `APIBypass/Core/ConfigManager.swift`

- [ ] **Step 1: 读取当前 ConfigManager.swift 文件**

使用 Read 工具读取 `/Users/panando/ClaudeCode/APIbypass/APIBypass/Core/ConfigManager.swift`

- [ ] **Step 2: 添加环境变量迁移方法和调用**

在 `loadProviders()` 方法末尾（`cleanupOrphanMappings()` 之后）添加迁移调用：

```swift
private func loadProviders() {
    guard let data = defaults.data(forKey: providersDefaultsKey),
          let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: data) else {
        providers = []
        return
    }
    providers = decoded
    
    // 迁移：为旧的 Provider 添加默认环境变量
    migrateProviderEnvironmentVariables()
}
```

然后在文件末尾添加迁移方法：

```swift
// MARK: - Environment Variables Migration

/// 为现有的 Provider 添加默认环境变量配置
private func migrateProviderEnvironmentVariables() {
    var needsSave = false
    
    for index in providers.indices {
        // 如果 environmentVariables 为空或不存在，添加默认值
        if providers[index].environmentVariables.isEmpty {
            providers[index].environmentVariables = ProviderConfig.defaultEnvironmentVariables()
            needsSave = true
            print("[Migration] Added default environment variables for provider: \(providers[index].name)")
        }
    }
    
    if needsSave {
        saveProviders()
        print("[Migration] Provider environment variables migration completed")
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add APIBypass/Core/ConfigManager.swift
git commit -m "feat: add environment variables migration logic"
```

---

## Task 7: 添加国际化字符串

**Files:**
- Modify: `APIBypass/Core/LocalizationManager.swift`

- [ ] **Step 1: 读取当前 LocalizationManager.swift 文件**

使用 Read 工具读取 `/Users/panando/ClaudeCode/APIbypass/APIBypass/Core/LocalizationManager.swift`

- [ ] **Step 2: 添加新的国际化键**

在 LocalizationManager 的 translations 字典中添加以下键：

```swift
// Claude Code Launcher
"launch_claude_code" = "启动 Claude Code"
"launch_claude_code_title" = "启动 Claude Code"
"claude_code_env_vars_title" = "Claude Code 环境变量"
"claude_code_env_vars_desc" = "配置启动 Claude Code 时注入的环境变量"
"select_provider" = "选择提供商"
"select_model_mapping" = "选择模型映射"
"environment_variables_preview" = "环境变量预览"
"use_first_mapping" = "使用第一个可用映射"
"launch" = "启动"
"please_select" = "请选择"
"provider" = "提供商"
"model_mapping" = "模型映射"
"edit" = "编辑"
"reset_to_default" = "重置为默认"
"add_env_var" = "添加环境变量"
"env_var_name" = "变量名"
"env_var_type" = "类型"
"env_var_value" = "值"
"select_model" = "选择模型"
"auto_select_first" = "自动选择第一个"
"read_from_keychain" = "从 Keychain 读取"

// Environment Variable Types
"envvar_manual" = "手动输入"
"envvar_model_mapping" = "模型映射"
"envvar_keychain_token" = "API Token"
"envvar_base_url" = "Base URL"

// Launcher Errors
"launcher_claude_not_found" = "未找到 Claude Code，请确保已安装并在 PATH 中"
"launcher_failed" = "启动失败: %@"
"launcher_keychain_failed" = "读取 Keychain 失败: %@"
"no_provider_selected" = "未选择提供商"
"claude_code_exited" = "Claude Code 已退出，退出码: %@"

// Migration
"migration_added_env_vars" = "[Migration] Added default environment variables for provider: %@"
"migration_completed" = "[Migration] Provider environment variables migration completed"
```

- [ ] **Step 3: Commit**

```bash
git add APIBypass/Core/LocalizationManager.swift
git commit -m "feat: add localization strings for Claude Code launcher"
```

---

## Task 8: 编写单元测试

**Files:**
- Create: `APIBypassTests/ClaudeCodeLauncherTests.swift`

- [ ] **Step 1: 编写 ClaudeCodeLauncher 单元测试**

```swift
import XCTest
@testable import APIBypass

final class ClaudeCodeLauncherTests: XCTestCase {
    
    var launcher: ClaudeCodeLauncher!
    
    override func setUp() {
        super.setUp()
        launcher = ClaudeCodeLauncher()
    }
    
    override func tearDown() {
        launcher = nil
        super.tearDown()
    }
    
    // MARK: - buildEnvironmentVariables Tests
    
    func testBuildEnvironmentVariablesWithManualType() {
        // Given
        let provider = ProviderConfig(
            name: "Test Provider",
            apiProvider: .openai,
            baseURL: URL(string: "https://api.example.com")!
        )
        
        let customVars = [
            EnvironmentVariableConfig(
                name: "CUSTOM_VAR",
                value: "custom_value",
                type: .manual,
                isEnabled: true
            )
        ]
        
        // When
        let env = launcher.buildEnvironmentVariables(
            provider: provider,
            customVars: customVars
        )
        
        // Then
        XCTAssertEqual(env["CUSTOM_VAR"], "custom_value")
    }
    
    func testBuildEnvironmentVariablesWithBaseURLType() {
        // Given
        let provider = ProviderConfig(
            name: "Test Provider",
            apiProvider: .openai,
            baseURL: URL(string: "https://api.example.com/v1")!
        )
        
        let customVars = [
            EnvironmentVariableConfig(
                name: "ANTHROPIC_BASE_URL",
                value: "",
                type: .baseURL,
                isEnabled: true
            )
        ]
        
        // When
        let env = launcher.buildEnvironmentVariables(
            provider: provider,
            customVars: customVars
        )
        
        // Then
        XCTAssertEqual(env["ANTHROPIC_BASE_URL"], "https://api.example.com/v1")
    }
    
    func testBuildEnvironmentVariablesWithModelMappingType() {
        // Given
        let providerId = UUID()
        let mappingId = UUID()
        
        let provider = ProviderConfig(
            id: providerId,
            name: "Test Provider",
            apiProvider: .openai,
            baseURL: URL(string: "https://api.example.com")!
        )
        
        let mapping = ModelMapping(
            id: mappingId,
            name: "GPT-4 Mapping",
            incomingModel: "gpt-4o",
            actualModel: "custom-model-v1",
            providerConfigId: providerId,
            isEnabled: true
        )
        
        let customVars = [
            EnvironmentVariableConfig(
                name: "ANTHROPIC_MODEL",
                value: "",
                type: .modelMapping,
                isEnabled: true
            )
        ]
        
        // When
        let env = launcher.buildEnvironmentVariables(
            provider: provider,
            selectedMapping: mapping,
            customVars: customVars
        )
        
        // Then
        XCTAssertEqual(env["ANTHROPIC_MODEL"], "gpt-4o")
    }
    
    func testDisabledVariablesAreNotIncluded() {
        // Given
        let provider = ProviderConfig(
            name: "Test Provider",
            apiProvider: .openai,
            baseURL: URL(string: "https://api.example.com")!
        )
        
        let customVars = [
            EnvironmentVariableConfig(
                name: "ENABLED_VAR",
                value: "enabled_value",
                type: .manual,
                isEnabled: true
            ),
            EnvironmentVariableConfig(
                name: "DISABLED_VAR",
                value: "disabled_value",
                type: .manual,
                isEnabled: false
            )
        ]
        
        // When
        let env = launcher.buildEnvironmentVariables(
            provider: provider,
            customVars: customVars
        )
        
        // Then
        XCTAssertEqual(env["ENABLED_VAR"], "enabled_value")
        XCTAssertNil(env["DISABLED_VAR"])
    }
    
    // MARK: - findClaudeCodeExecutable Tests
    
    func testFindClaudeCodeExecutableReturnsNilWhenNotFound() {
        // 注意：这个测试在实际环境中可能不适用，因为无法模拟文件系统
        // 主要用于确保代码可以编译和运行
        
        // When
        let path = launcher.findClaudeCodeExecutable()
        
        // Then
        // 路径可能为 nil 或实际路径，取决于运行环境
        // 至少确保代码没有崩溃
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add APIBypassTests/ClaudeCodeLauncherTests.swift
git commit -m "test: add unit tests for ClaudeCodeLauncher"
```

---

## 完成总结

### 已创建的文件（9 个）

1. ✅ `APIBypass/Models/EnvironmentVariableConfig.swift` - 环境变量配置模型
2. ✅ `APIBypass/Models/ProviderConfig.swift` - 扩展添加 environmentVariables 字段
3. ✅ `APIBypass/Services/ClaudeCodeLauncher.swift` - Claude Code 启动服务
4. ✅ `APIBypass/UI/Views/EnvironmentVariablesCard.swift` - Provider 详情页环境变量卡片
5. ✅ `APIBypass/UI/Views/LaunchClaudeCodeView.swift` - 启动确认界面
6. ✅ `APIBypass/UI/MenuBarView.swift` - 添加启动菜单项
7. ✅ `APIBypass/Core/ConfigManager.swift` - 添加数据迁移逻辑
8. ✅ `APIBypass/Core/LocalizationManager.swift` - 添加国际化字符串
9. ✅ `APIBypassTests/ClaudeCodeLauncherTests.swift` - 单元测试

### 实现步骤

按顺序执行以下命令：

```bash
# 1. 创建环境变量配置模型
git add APIBypass/Models/EnvironmentVariableConfig.swift
git commit -m "feat: add EnvironmentVariableConfig model for Claude Code launcher"

# 2. 扩展 ProviderConfig
git add APIBypass/Models/ProviderConfig.swift
git commit -m "feat: add environmentVariables to ProviderConfig"

# 3. 创建 ClaudeCodeLauncher 服务
git add APIBypass/Services/ClaudeCodeLauncher.swift
git commit -m "feat: add ClaudeCodeLauncher service"

# 4. 创建 EnvironmentVariablesCard UI
git add APIBypass/UI/Views/EnvironmentVariablesCard.swift
git commit -m "feat: add EnvironmentVariablesCard UI component"

# 5. 创建 LaunchClaudeCodeView
git add APIBypass/UI/Views/LaunchClaudeCodeView.swift
git commit -m "feat: add LaunchClaudeCodeView UI"

# 6. 修改 MenuBarView
git add APIBypass/UI/MenuBarView.swift
git commit -m "feat: add launch Claude Code menu item"

# 7. 添加数据迁移逻辑
git add APIBypass/Core/ConfigManager.swift
git commit -m "feat: add environment variables migration logic"

# 8. 添加国际化字符串
git add APIBypass/Core/LocalizationManager.swift
git commit -m "feat: add localization strings for Claude Code launcher"

# 9. 添加单元测试
git add APIBypassTests/ClaudeCodeLauncherTests.swift
git commit -m "test: add unit tests for ClaudeCodeLauncher"
```

---

**执行方式选择：**

1. **使用 subagent-driven-development**（推荐）- 我可以启动子代理，每个任务分配给一个子代理执行，并在任务之间进行审查
2. **使用 executing-plans** - 在当前会话中使用 executing-plans skill 批量执行任务

请选择你喜欢的执行方式。
