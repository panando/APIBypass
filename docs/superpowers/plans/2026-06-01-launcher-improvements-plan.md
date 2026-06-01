# Launch Claude Code 界面改进实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 LaunchClaudeCodeView 添加三个功能：工作目录历史下拉、配置模板管理、终端进程检测弹窗

**Architecture:** 所有新数据用 UserDefaults JSON 持久化，通过 `@AppStorage` 兼容的属性模式读写。`LaunchTemplate`/`TerminalLaunchMode` 追加在 `ClaudeCodeLauncher.swift` 中。UI 变更集中在 `LaunchClaudeCodeView.swift`，本地化 key 追加到 `LocalizationManager.swift`

**Tech Stack:** SwiftUI, AppStorage/UserDefaults, AppleScript (osascript)

---

### Task 1: 添加数据模型和存储辅助方法

**Files:**
- Modify: `APIBypass/Services/ClaudeCodeLauncher.swift`

- [ ] **Step 1: 在 ClaudeCodeLauncher.swift 顶部（TerminalApp 定义之后）追加 LaunchTemplate 和 TerminalLaunchMode**

在 `struct TerminalApp: Identifiable, Equatable` 的定义结束 `}` 后、`enum LauncherError` 前插入：

```swift
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
        subagentModelProviderId: String? = nil
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
    }
}

/// 终端启动模式
enum TerminalLaunchMode: String, Codable {
    case newWindow
    case newTab
}
```

- [ ] **Step 2: 在 LaunchConfiguration 中追加 launchMode 字段**

找到 `struct LaunchConfiguration`，在现有字段后添加 `launchMode`：

```swift
struct LaunchConfiguration {
    let provider: ProviderConfig
    let selectedMapping: ModelMapping?
    let customEnvVars: [String: String]
    let workingDirectory: URL?
    let disableAttributionHeader: Bool
    let launchMode: TerminalLaunchMode  // 新增
}
```

- [ ] **Step 3: 在 ClaudeCodeLauncher 类中添加模板读写静态方法**

在 `ClaudeCodeLauncher` 类的 `// MARK: - 1M context detection` mark 前，追加：

```swift
    // MARK: - Template Persistence

    private static let templatesKey = "launcher.templates"
    private static let recentDirectoriesKey = "launcher.recentDirectories"

    static func loadTemplates() -> [LaunchTemplate] {
        guard let data = UserDefaults.standard.data(forKey: templatesKey),
              let decoded = try? JSONDecoder().decode([LaunchTemplate].self, from: data) else {
            return []
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
        // 去重：移除已有相同路径
        dirs.removeAll { $0 == path }
        // 插到开头
        dirs.insert(path, at: 0)
        // 保留最多 5 个
        if dirs.count > 5 { dirs = Array(dirs.prefix(5)) }
        saveRecentDirectories(dirs)
    }
```

- [ ] **Step 4: 提交**

```bash
git add APIBypass/Services/ClaudeCodeLauncher.swift
git commit -m "feat: add LaunchTemplate and TerminalLaunchMode models with persistence helpers"
```

---

### Task 2: 添加终端进程检测和标签页/窗口 AppleScript 支持

**Files:**
- Modify: `APIBypass/Services/ClaudeCodeLauncher.swift`

- [ ] **Step 1: 添加 isTerminalRunning 静态方法**

在 `ClaudeCodeLauncher` 的 `// MARK: - 终端检测` mark 区域末尾（`availableTerminals()` 方法之后）追加：

```swift
    /// 检测指定终端是否已有实例在运行
    static func isTerminalRunning(_ terminal: TerminalApp) -> Bool {
        guard let bundleId = terminal.bundleId else { return false }
        return !NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleId
        ).isEmpty
    }
```

- [ ] **Step 2: 重构 TerminalApp — 添加 launchWindowCommand 和 launchTabCommand**

修改 `TerminalApp` 结构体的属性定义：

```swift
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
```

- [ ] **Step 3: 为 Terminal.app 添加标签页/窗口命令**

找到 Terminal.app 的初始化（`id: "terminal"` 那段），扩展 `launchCommand` 闭包并新增 `launchWindowCommand` 和 `launchTabCommand`：

```swift
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
```

- [ ] **Step 4: 为 iTerm2 添加标签页/窗口命令**

找到 iTerm2 的初始化（`id: "iterm2"` 那段）：

```swift
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
                    },
                    launchWindowCommand: { claudePath, envVars, workDir in
                        let envExports = envVars.map { "export \($0.key)='\($0.value)'" }.joined(separator: " && ")
                        let cdCommand = workDir != nil ? "cd '\(workDir!)' && " : ""
                        return "tell application \"iTerm2\"\nactivate\ncreate window with default profile\ntell current session of current window\nwrite text \"\(cdCommand)\(envExports) && \(claudePath)\"\nend tell\nend tell"
                    },
                    launchTabCommand: { claudePath, envVars, workDir in
                        let envExports = envVars.map { "export \($0.key)='\($0.value)'" }.joined(separator: " && ")
                        let cdCommand = workDir != nil ? "cd '\(workDir!)' && " : ""
                        return "tell application \"iTerm2\"\nactivate\ntell current window\ncreate tab with default profile\ntell current session\nwrite text \"\(cdCommand)\(envExports) && \(claudePath)\"\nend tell\nend tell\nend tell"
                    }
                ))
                break
            }
        }
```

- [ ] **Step 5: 为其他终端（Alacritty, Kitty, Warp, Hyper）添加 nil 的 launchWindowCommand/launchTabCommand**

找到 Alacritty、Kitty、Warp、Hyper 的初始化，在现有的 `launchCommand:` 参数后各添加：

```swift
                launchWindowCommand: nil,
                launchTabCommand: nil
```

- [ ] **Step 6: 修改 launchInTerminal 方法签名和实现**

修改 `launchInTerminal` 方法，使用 `launchMode` 选择正确的命令闭包：

```swift
    func launchInTerminal(terminal: TerminalApp, configuration: LaunchConfiguration) throws {
        guard let claudePath = findClaudeCodeExecutable() else {
            throw LauncherError.claudeCodeNotFound
        }

        var envVars = configuration.customEnvVars
        for (key, value) in configuration.customEnvVars {
            envVars[key] = value
        }
        if configuration.disableAttributionHeader {
            envVars["CLAUDE_CODE_ATTRIBUTION_HEADER"] = "0"
        }

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

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        do {
            try task.run()
        } catch {
            throw LauncherError.launchFailed(error.localizedDescription)
        }
    }
```

- [ ] **Step 7: 构建验证编译**

```bash
swift build
```
预期：BUILD SUCCESS

- [ ] **Step 8: 提交**

```bash
git add APIBypass/Services/ClaudeCodeLauncher.swift
git commit -m "feat: add terminal process detection and tab/window launch support"
```

---

### Task 3: 工作目录历史下拉菜单

**Files:**
- Modify: `APIBypass/UI/Views/LaunchClaudeCodeView.swift`

- [ ] **Step 1: 添加 @State 变量和加载方法**

在 `LaunchClaudeCodeView` 结构体中，在现有 `@State` 变量区域（`@State private var rectifierEnabled: Bool = true` 之后、`@State private var isLaunching = false` 之前）添加：

```swift
    @State private var recentDirectories: [String] = []
```

在 `loadSavedSettings()` 方法末尾追加：

```swift
        recentDirectories = ClaudeCodeLauncher.loadRecentDirectories()
```

- [ ] **Step 2: 替换工作目录 UI 区域**

将现有的工作目录选择区域（`// 工作目录选择` 注释下方的 `HStack`，约第 228-243 行）替换为：

```swift
            // 工作目录选择
            HStack(spacing: 16) {
                Text(L10n.t("working_directory"))
                    .font(.headline)
                    .frame(width: 100, alignment: .leading)

                Menu {
                    if recentDirectories.isEmpty {
                        Text(L10n.t("no_recent_dirs"))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(recentDirectories, id: \.self) { path in
                            Button {
                                workingDirectory = path
                            } label: {
                                Text(path)
                                    .truncationMode(.middle)
                                    .lineLimit(1)
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            recentDirectories = []
                            ClaudeCodeLauncher.saveRecentDirectories([])
                        } label: {
                            Label(L10n.t("clear_history"), systemImage: "trash")
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(workingDirectory.isEmpty ? L10n.t("working_directory_hint") : workingDirectory)
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .foregroundColor(workingDirectory.isEmpty ? .secondary : .primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
                .menuIndicator(.visible)

                Button {
                    showDirectoryPicker = true
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
            }
```

- [ ] **Step 3: 在 launchClaudeCode() 中记录历史目录**

在 `launchClaudeCode()` 方法的 `dismiss()` 调用之前（`try launcher.launchInTerminal(...)` 之后），添加：

```swift
            // 记录工作目录到历史
            if !workingDirectory.isEmpty {
                ClaudeCodeLauncher.addRecentDirectory(workingDirectory)
            }
            dismiss()
```

- [ ] **Step 4: 在 saveSettings() 中不持久化 recentDirectories**

recentDirectories 通过 ClaudeCodeLauncher 的静态方法管理，不在 saveSettings() 中处理。确认 `saveSettings()` 方法中没有额外操作——无需修改。

- [ ] **Step 5: 构建验证编译**

```bash
swift build
```
预期：BUILD SUCCESS（可能因缺少本地化 key 告警，但编译通过，Task 6 补齐 key）

- [ ] **Step 6: 提交**

```bash
git add APIBypass/UI/Views/LaunchClaudeCodeView.swift
git commit -m "feat: add recent directories dropdown to working directory picker"
```

---

### Task 4: 配置模板管理

**Files:**
- Modify: `APIBypass/UI/Views/LaunchClaudeCodeView.swift`

- [ ] **Step 1: 添加模板相关 @State 变量**

在 `@State private var recentDirectories: [String] = []` 之后追加：

```swift
    @State private var templates: [LaunchTemplate] = []
    @State private var activeTemplateName: String? = nil
    @State private var showSaveTemplateSheet = false
    @State private var showRenameTemplateSheet = false
    @State private var showDeleteTemplateConfirm = false
    @State private var newTemplateName = ""
    @State private var renameTarget: LaunchTemplate?
    @State private var renameText = ""
```

在 `loadSavedSettings()` 末尾追加：

```swift
        templates = ClaudeCodeLauncher.loadTemplates()
        if let savedName = UserDefaults.standard.string(forKey: "launcher.activeTemplateName"),
           templates.contains(where: { $0.name == savedName }) {
            activeTemplateName = savedName
        }
```

- [ ] **Step 2: 添加模板操作方法**

在 `LaunchClaudeCodeView` 的 `// MARK: - Persistence` region 内，`saveSettings()` 方法之后，添加模板操作方法：

```swift
    private func applyTemplate(_ tmpl: LaunchTemplate) {
        savedAnthropicModel = tmpl.anthropicModel
        savedAnthropicModelProviderId = tmpl.anthropicModelProviderId
        savedOpusModel = tmpl.opusModel
        savedOpusModelProviderId = tmpl.opusModelProviderId
        savedSonnetModel = tmpl.sonnetModel
        savedSonnetModelProviderId = tmpl.sonnetModelProviderId
        savedHaikuModel = tmpl.haikuModel
        savedHaikuModelProviderId = tmpl.haikuModelProviderId
        savedSubagentModel = tmpl.subagentModel
        savedSubagentModelProviderId = tmpl.subagentModelProviderId
        activeTemplateName = tmpl.name
        UserDefaults.standard.set(tmpl.name, forKey: "launcher.activeTemplateName")
    }

    private func saveCurrentAsTemplate(name: String) {
        let newTemplate = LaunchTemplate(
            name: name,
            anthropicModel: savedAnthropicModel,
            anthropicModelProviderId: savedAnthropicModelProviderId,
            opusModel: savedOpusModel,
            opusModelProviderId: savedOpusModelProviderId,
            sonnetModel: savedSonnetModel,
            sonnetModelProviderId: savedSonnetModelProviderId,
            haikuModel: savedHaikuModel,
            haikuModelProviderId: savedHaikuModelProviderId,
            subagentModel: savedSubagentModel,
            subagentModelProviderId: savedSubagentModelProviderId
        )
        templates.append(newTemplate)
        ClaudeCodeLauncher.saveTemplates(templates)
    }

    private func deleteTemplate(_ tmpl: LaunchTemplate) {
        templates.removeAll { $0.id == tmpl.id }
        ClaudeCodeLauncher.saveTemplates(templates)
        if activeTemplateName == tmpl.name {
            activeTemplateName = nil
            UserDefaults.standard.removeObject(forKey: "launcher.activeTemplateName")
        }
    }

    private func renameTemplate(_ tmpl: LaunchTemplate, to newName: String) {
        if let index = templates.firstIndex(where: { $0.id == tmpl.id }) {
            templates[index].name = newName
            ClaudeCodeLauncher.saveTemplates(templates)
            if activeTemplateName == tmpl.name {
                activeTemplateName = newName
                UserDefaults.standard.set(newName, forKey: "launcher.activeTemplateName")
            }
        }
    }

    private func markTemplateDirty() {
        activeTemplateName = nil
        UserDefaults.standard.removeObject(forKey: "launcher.activeTemplateName")
    }
```

- [ ] **Step 3: 在 UI 中插入模板栏**

在 `selectionSection` 的结束 `}` 之后、`Divider()` 之前（即 `selectionSection` 和 `Divider()` 之间），插入模板栏：

```swift
                    // 配置模板
                    HStack(spacing: 16) {
                        Text(L10n.t("config_template"))
                            .font(.headline)
                            .frame(width: 100, alignment: .leading)

                        Menu {
                            if templates.isEmpty {
                                Text(L10n.t("no_templates"))
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(templates) { tmpl in
                                    Button {
                                        applyTemplate(tmpl)
                                    } label: {
                                        HStack {
                                            Text(tmpl.name)
                                            if activeTemplateName == tmpl.name {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            Divider()
                            Button {
                                newTemplateName = ""
                                showSaveTemplateSheet = true
                            } label: {
                                Label(L10n.t("save_as_template"), systemImage: "plus")
                            }
                        } label: {
                            Text(activeTemplateName ?? L10n.t("default_template"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .menuIndicator(.visible)

                        if activeTemplateName != nil {
                            Button {
                                renameText = activeTemplateName ?? ""
                                showRenameTemplateSheet = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                showDeleteTemplateConfirm = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
```

- [ ] **Step 4: 在模型参数变更时触发 markTemplateDirty**

在每个模型 picker 的 `.onChange` 中调用 `markTemplateDirty()`。找到以下 `@AppStorage` 变量的 onChange 位置：`savedAnthropicModel`、`savedOpusModel`、`savedSonnetModel`、`savedHaikuModel`、`savedSubagentModel`。这些变量没有直接的 `.onChange` 修饰，但 picker 绑定是双向的。需要在 `saveSettings()` 中检测模板是否已变脏。

更简洁的做法：在 `saveSettings()` 方法末尾添加模板检查逻辑。但模型参数是 `@AppStorage` 直接绑定的，没有经过 `saveSettings()`。

更好的方案：不通过 onChange，而是在 `applyTemplate` 中设置 `activeTemplateName`，在用户通过 UI 修改任何模型参数时通过 `saveSettings()` 检查——但当前 saveSettings 不处理模型参数。

最简方案：为每个模型 `@AppStorage` 变量添加 onChange 修饰。在 `body` 中已有多个 `.onChange`，我们可以添加一个集中的模板脏检测。

实际做法：为 ANTHROPIC_MODEL 的 picker 添加 onChange（它已经在第 413-431 行的 `modelPickerRow` 中）。`modelPickerRow` 已有 onChange 用于清空 model 值。我们可以扩展现有的 onChange 或在每个 picker 的 onChange 中同时调用 markTemplateDirty。

最简实现——在 `modelPickerRow` 内的 `picker.onChange(of: providerId.wrappedValue)` 闭包中也调用 markTemplateDirty。但由于 modelPickerRow 是 ViewBuilder 函数，无法访问 self。

实际最简：在 `selectionSection` 中每个模型行使用的 `$savedAnthropicModel` 等变量，在 `saveSettings()` 的调用处（即所有 `.onChange` 闭包中）不需要处理——用户操作 picker 就是选择模板后的自定义，此时自然不希望还显示"模板名"。

**替换方案**：不依赖 onChange，而是在 `applyTemplate` 之外的**所有用户操作都会触发 saveSettings**，我们可以在 saveSettings() 中与模板快照比较。但这样过于复杂。

**最终简化方案**：添加一个辅助方法，当用户在 UI 中修改了任何一个模型参数后，才检测模板是否匹配。实际检测时机放在用户选择 provider 或 model 的 onChange 中，这些 onChange 已经在 modelPickerRow 里。

由于 modelPickerRow 是内联函数返回 View，我们可以直接在各处 onChange 闭包中添加 `markTemplateDirty()` 调用。最简改动点：

在 `// 终端选择` 下方的 `.onChange(of: selectedTerminalId)` 闭包里不需要改（终端不是模板的一部分）。

找到 `modelPickerRow` 函数的定义，在 `providerId` 的 onChange 和 `model` 的 onChange 中添加标记。但由于这是函数返回的 View，标记不能在函数内调用 self 的方法...

让我换个思路：直接在 `body` 中已有的 onChange 之后做，或者让每个 @AppStorage 变量的变化通过 Combine 来检测。

**最简实际做法**：不在每个 onChange 中调用，而是在用户选择模板后的「下次界面刷新时检查」——由于所有模型参数都是通过 Binding 双向绑定的，当用户改变 picker 时 `savedAnthropicModel` 等直接变化。我们可以在 `saveSettings()` 中检查（当终端、目录、effort 等变化时调用 saveSettings，但模板参数变化不调用 saveSettings）。

**最终方案**：为每个模型 @AppStorage 变量在 view 的 onChange modifier 中添加检测——但 SwiftUI 中 `@AppStorage` 变量没有自动的 onChange... 可以使用 `onChange(of:)` modifier 在 body 上。

实际上最简单的方式：不做自动检测。让用户手动管理模板。只有当用户**主动选择另一个模板**时才会切换。删除当前模板时清空 activeTemplateName。用户修改参数后如果不保存，activeTemplateName 还在但参数已经是自定义的了——这不完美但足够简单。

**最简可用方案**：取消自动 dirty 检测。规则变为：
- 选择模板 → 填充参数，设置 activeTemplateName
- 用户可随意修改参数 → activeTemplateName 不变（作为提示"基于哪个模板修改的"）
- 用户可以保存新模板、重命名当前模板、删除模板
- 删除当前模板 → activeTemplateName 清空

这个方案更简单，且用户体验也不错。不需要 markTemplateDirty 方法。

这样的话，保留 activeTemplateName 相关逻辑但去掉 markTemplateDirty 调用。模板栏的重命名/删除按钮始终在 activeTemplateName != nil 时显示。

- [ ] **Step 5: 添加 Sheet — 保存新模板**

在 `body` 末尾（`}` 之前，与 `.fileImporter` 并列）追加 3 个 sheet：

```swift
        .sheet(isPresented: $showSaveTemplateSheet) {
            VStack(spacing: 16) {
                Text(L10n.t("save_as_template"))
                    .font(.headline)
                TextField(L10n.t("template_name"), text: $newTemplateName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                HStack(spacing: 12) {
                    Button(L10n.t("cancel")) {
                        showSaveTemplateSheet = false
                    }
                    .keyboardShortcut(.escape)
                    Button(L10n.t("save")) {
                        let name = newTemplateName.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            // 同名覆盖
                            templates.removeAll { $0.name == name }
                            saveCurrentAsTemplate(name: name)
                            activeTemplateName = name
                            UserDefaults.standard.set(name, forKey: "launcher.activeTemplateName")
                            showSaveTemplateSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTemplateName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return)
                }
            }
            .padding(24)
            .frame(width: 350, height: 150)
        }
```

- [ ] **Step 6: 添加 Sheet — 重命名模板**

在保存模板 sheet 后追加：

```swift
        .sheet(isPresented: $showRenameTemplateSheet) {
            VStack(spacing: 16) {
                Text(L10n.t("rename_template"))
                    .font(.headline)
                TextField(L10n.t("template_name"), text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                HStack(spacing: 12) {
                    Button(L10n.t("cancel")) {
                        showRenameTemplateSheet = false
                    }
                    .keyboardShortcut(.escape)
                    Button(L10n.t("save")) {
                        let newName = renameText.trimmingCharacters(in: .whitespaces)
                        if !newName.isEmpty, let target = templates.first(where: { $0.name == activeTemplateName }) {
                            renameTemplate(target, to: newName)
                            showRenameTemplateSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return)
                }
            }
            .padding(24)
            .frame(width: 350, height: 150)
        }
```

- [ ] **Step 7: 添加 Alert — 删除确认**

在 body 末尾的 `}` 之前添加 alert modifier：

```swift
        .alert(L10n.t("delete_template"), isPresented: $showDeleteTemplateConfirm) {
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("delete"), role: .destructive) {
                if let target = templates.first(where: { $0.name == activeTemplateName }) {
                    deleteTemplate(target)
                }
            }
        } message: {
            Text(L10n.format("delete_template_confirm", activeTemplateName ?? ""))
        }
```

- [ ] **Step 8: 构建验证编译**

```bash
swift build
```
预期：BUILD SUCCESS

- [ ] **Step 9: 提交**

```bash
git add APIBypass/UI/Views/LaunchClaudeCodeView.swift
git commit -m "feat: add model config template save/load/rename/delete"
```

---

### Task 5: 终端进程检测弹窗

**Files:**
- Modify: `APIBypass/UI/Views/LaunchClaudeCodeView.swift`

- [ ] **Step 1: 添加 Alert 状态变量**

在现有 `@State` 变量区域追加：

```swift
    @State private var showTerminalRunningAlert = false
    @State private var pendingTerminal: TerminalApp?
```

- [ ] **Step 2: 修改 launchClaudeCode() 方法**

将 `launchClaudeCode()` 方法替换为：

```swift
    private func launchClaudeCode() {
        guard let terminal = selectedTerminal else {
            errorMessage = L10n.t("no_terminal_selected")
            return
        }
        guard let defaultProvider = anthropicModelProviderBinding.wrappedValue.flatMap({ configManager.findProvider(for: $0) }) else {
            errorMessage = L10n.t("no_provider_selected")
            return
        }

        isLaunching = true
        errorMessage = nil

        // 检测终端是否已运行
        if ClaudeCodeLauncher.isTerminalRunning(terminal) {
            isLaunching = false
            pendingTerminal = terminal
            showTerminalRunningAlert = true
            return
        }

        doLaunch(terminal: terminal, provider: defaultProvider, mode: .newWindow)
    }

    private func doLaunch(terminal: TerminalApp, provider: ProviderConfig, mode: TerminalLaunchMode) {
        isLaunching = true
        errorMessage = nil

        var customEnvVars: [String: String] = [
            "ANTHROPIC_BASE_URL": localBaseURL,
            "ANTHROPIC_AUTH_TOKEN": "1234",
            "ANTHROPIC_MODEL": ClaudeCodeLauncher.with1MContextSuffix(savedAnthropicModel)
        ]

        if !savedOpusModel.isEmpty { customEnvVars["ANTHROPIC_DEFAULT_OPUS_MODEL"] = ClaudeCodeLauncher.with1MContextSuffix(savedOpusModel) }
        if !savedSonnetModel.isEmpty { customEnvVars["ANTHROPIC_DEFAULT_SONNET_MODEL"] = ClaudeCodeLauncher.with1MContextSuffix(savedSonnetModel) }
        if !savedHaikuModel.isEmpty { customEnvVars["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = ClaudeCodeLauncher.with1MContextSuffix(savedHaikuModel) }
        if !savedSubagentModel.isEmpty { customEnvVars["CLAUDE_CODE_SUBAGENT_MODEL"] = ClaudeCodeLauncher.with1MContextSuffix(savedSubagentModel) }
        if !effortLevel.isEmpty { customEnvVars["CLAUDE_CODE_EFFORT_LEVEL"] = effortLevel }

        let workDir = workingDirectory.isEmpty ? nil : URL(fileURLWithPath: workingDirectory)

        let launcher = ClaudeCodeLauncher()
        let configuration = LaunchConfiguration(
            provider: provider,
            selectedMapping: nil,
            customEnvVars: customEnvVars,
            workingDirectory: workDir,
            disableAttributionHeader: disableAttributionHeader,
            launchMode: mode
        )

        do {
            try launcher.launchInTerminal(terminal: terminal, configuration: configuration)
            if !workingDirectory.isEmpty {
                ClaudeCodeLauncher.addRecentDirectory(workingDirectory)
            }
            dismiss()
        } catch {
            isLaunching = false
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 3: 在 body 末尾添加终端运行检测 Alert**

在 `.alert(L10n.t("delete_template"), ...)` 之后追加：

```swift
        .alert(L10n.t("terminal_already_running"), isPresented: $showTerminalRunningAlert) {
            Button(L10n.t("new_tab")) {
                if let terminal = pendingTerminal,
                   let provider = anthropicModelProviderBinding.wrappedValue.flatMap({ configManager.findProvider(for: $0) }) {
                    doLaunch(terminal: terminal, provider: provider, mode: .newTab)
                }
            }
            Button(L10n.t("new_window")) {
                if let terminal = pendingTerminal,
                   let provider = anthropicModelProviderBinding.wrappedValue.flatMap({ configManager.findProvider(for: $0) }) {
                    doLaunch(terminal: terminal, provider: provider, mode: .newWindow)
                }
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.format("terminal_running_message", pendingTerminal?.name ?? ""))
        }
```

- [ ] **Step 4: 构建验证编译**

```bash
swift build
```
预期：BUILD SUCCESS

- [ ] **Step 5: 提交**

```bash
git add APIBypass/UI/Views/LaunchClaudeCodeView.swift
git commit -m "feat: add terminal process detection alert with tab/window choice"
```

---

### Task 6: 添加本地化 Key

**Files:**
- Modify: `APIBypass/Core/LocalizationManager.swift`

- [ ] **Step 1: 在 L10n.dict 末尾添加新 key**

注意：每个 key 对应 `.chinese` 和 `.english` 两个翻译，以 `],` 结尾。

在 `"param_presence_penalty"` 这一行之后（第 243 行 `]` 之前），追加：

```swift
        // 工作目录历史
        "no_recent_dirs": [.chinese: "暂无历史目录", .english: "No Recent Directories"],
        "clear_history": [.chinese: "清除历史", .english: "Clear History"],

        // 配置模板
        "config_template": [.chinese: "配置模板", .english: "Config Template"],
        "default_template": [.chinese: "默认", .english: "Default"],
        "no_templates": [.chinese: "暂无模板", .english: "No Templates"],
        "save_as_template": [.chinese: "保存为新模板...", .english: "Save as Template..."],
        "rename_template": [.chinese: "重命名模板", .english: "Rename Template"],
        "delete_template": [.chinese: "删除模板", .english: "Delete Template"],
        "delete_template_confirm": [.chinese: "确定要删除模板 {name} 吗？此操作无法撤销。", .english: "Delete template {name}? This cannot be undone."],
        "template_name": [.chinese: "模板名称", .english: "Template Name"],
        "save": [.chinese: "保存", .english: "Save"],

        // 终端检测
        "terminal_already_running": [.chinese: "终端已在运行", .english: "Terminal Already Running"],
        "terminal_running_message": [.chinese: "{name} 已在运行，请选择启动方式", .english: "{name} is already running. Choose launch mode."],
        "new_tab": [.chinese: "新建标签页", .english: "New Tab"],
        "new_window": [.chinese: "新建窗口", .english: "New Window"],
```

- [ ] **Step 2: 构建验证编译**

```bash
swift build
```
预期：BUILD SUCCESS

- [ ] **Step 3: 提交**

```bash
git add APIBypass/Core/LocalizationManager.swift
git commit -m "feat: add localization keys for launcher improvements"
```

---

### Task 7: 完整构建验证

**目的：** 确保所有改动编译通过、无语法错误

- [ ] **Step 1: 完整构建**

```bash
swift build -c release 2>&1
```
预期：BUILD SUCCESS，无 warning

- [ ] **Step 2: 运行测试**

```bash
swift test 2>&1
```
预期：所有已有测试通过

- [ ] **Step 3: 检查 git diff**

```bash
git diff --stat main
```
确认只有 3 个文件被修改，无意外变更。

- [ ] **Step 4: 最终检查清单**

- [ ] 工作目录 Menu 下拉包含历史路径
- [ ] 历史路径去重、最多 5 个
- [ ] 模板下拉可选择/保存/重命名/删除
- [ ] 终端检测 Alert 正确弹出
- [ ] 中英文本地化完整
