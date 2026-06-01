# Launch Claude Code 界面改进设计

## 背景

当前 LaunchClaudeCodeView 的三个痛点：
1. 工作目录每次都要手动输入或通过文件夹选择器重新选择，频繁切换项目时效率低
2. 模型配置参数（5 个模型 + effort level 等）需要逐个修改，没有一键切换常用配置的能力
3. 启动时直接打开终端，不检测终端是否已在运行，导致用户手动处理窗口/标签页冲突

## 范围

三个独立功能：
1. 工作目录下拉菜单（记住最近 5 个路径）
2. 配置模板（保存/重命名/删除模型参数组合）
3. 终端进程检测 + 标签页/窗口选择弹窗

不包含：effort level、attribution header、rectifier 等非模型参数不纳入模板。

## 数据模型

### LaunchTemplate

```swift
struct LaunchTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var anthropicModel: String
    var anthropicModelProviderId: UUID?
    var opusModel: String
    var opusModelProviderId: UUID?
    var sonnetModel: String
    var sonnetModelProviderId: UUID?
    var haikuModel: String
    var haikuModelProviderId: UUID?
    var subagentModel: String
    var subagentModelProviderId: UUID?
}
```

### TerminalLaunchMode

```swift
enum TerminalLaunchMode: String, Codable {
    case newWindow
    case newTab
}
```

### LaunchConfiguration 变更

在现有 `LaunchConfiguration` 中新增字段：
```swift
let launchMode: TerminalLaunchMode
```

### 存储

全部使用 `@AppStorage`：

| Key | 类型 | 说明 |
|-----|------|------|
| `launcher.templates` | `[LaunchTemplate]` JSON | 模板列表 |
| `launcher.recentDirectories` | `[String]` JSON | 最近 5 个工作目录 |
| `launcher.activeTemplateName` | `String?` | 当前选中的模板名 |

## UI 设计

### 1. 工作目录下拉菜单

将当前的 `TextField` + 文件夹按钮改为 `Menu` + 文件夹按钮：

```
HStack(spacing: 16) {
    Text("工作目录").font(.headline).frame(width: 100)

    Menu {
        ForEach(recentDirectories, id: \.self) { path in
            Button(path) { workingDirectory = path }
        }
        if !recentDirectories.isEmpty {
            Divider()
            Button("清除历史") { recentDirectories = [] }
        }
    } label: {
        Text(workingDirectory.isEmpty ? "留空使用主目录" : workingDirectory)
            .truncationMode(.middle).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    Button { showDirectoryPicker = true } label: {
        Image(systemName: "folder")
    }.buttonStyle(.bordered)
}
```

**历史记录更新逻辑**：
- `launchClaudeCode()` 成功后调用 `addToRecentDirectories(workingDirectory)`
- 去重、限制 5 个、空路径不记录

### 2. 配置模板管理

在环境变量区域上方新增模板栏：

```
HStack {
    Text("配置模板").font(.headline)

    Menu {
        ForEach(templates) { tmpl in
            Button(tmpl.name) { applyTemplate(tmpl) }
        }
        Divider()
        Button("保存为新模板...") { showSaveTemplateSheet = true }
    } label: {
        Text(activeTemplateName ?? "默认")
    }

    if activeTemplateName != nil {
        Button("重命名") { showRenameSheet = true }
        Button("删除") { showDeleteConfirm = true }
    }
    Spacer()
}
```

**交互规则**：
- 选择模板 → 填充 5 个模型参数到 `@AppStorage`
- 保存模板 → Sheet 输入名称，保存当前 5 个模型参数
- 重命名 → Sheet 输入新名称
- 删除 → Alert 确认
- 用户手动修改任意模型参数 → `activeTemplateName` 置 nil

### 3. 终端进程检测

**新增 `ClaudeCodeLauncher` 方法**：
```swift
static func isTerminalRunning(_ terminal: TerminalApp) -> Bool {
    guard let bundleId = terminal.bundleId else { return false }
    return !NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleId
    ).isEmpty
}
```

**启动流程变更**：

```
用户点击「启动」
  ↓
终端未运行？ → 直接启动（现有逻辑）
终端已运行？ → 弹 Alert：
  [新建标签页] [新建窗口] [取消]
  ↓
选择后，修改 AppleScript 命令：
```

**各终端的标签页/窗口 AppleScript**：

| 终端 | 新窗口 | 新标签页 |
|------|--------|---------|
| Terminal.app | `do script "<cmd>"` | `do script "<cmd>" in front window` |
| iTerm2 | `create window with default profile` + `write text` | `create tab with default profile` + `write text` |
| Kitty | `launch --type=window` | `launch --type=tab` |
| Alacritty | 不支持标签页，始终新窗口 | N/A |
| Warp | `do script "<cmd>" in new window` | `do script "<cmd>"` |
| Hyper | 类似 Terminal.app | 类似 Terminal.app |

**TerminalApp 结构变更**：
将 `launchCommand` 从单一闭包改为两个闭包：
```swift
let launchCommand: (String, [String: String], String?) -> String  // 保留作默认
let launchWindowCommand: ((String, [String: String], String?) -> String)?  // 新窗口
let launchTabCommand: ((String, [String: String], String?) -> String)?     // 新标签页
```

## 文件变更清单

| 文件 | 变更 |
|------|------|
| `APIBypass/UI/Views/LaunchClaudeCodeView.swift` | 主要改动：模板栏、下拉菜单、终端检测弹窗 |
| `APIBypass/Services/ClaudeCodeLauncher.swift` | 新增 `isTerminalRunning`、拆分标签页/窗口命令、`launchMode` 字段 |
| `APIBypass/Core/LocalizationManager.swift` | 新增本地化 key |

## 本地化 Key 新增

```
"recent_directories" — "最近目录" / "Recent Directories"
"clear_history" — "清除历史" / "Clear History"
"config_template" — "配置模板" / "Config Template"
"default_template" — "默认" / "Default"
"save_as_template" — "保存为新模板..." / "Save as Template..."
"rename_template" — "重命名" / "Rename"
"delete_template" — "删除模板" / "Delete Template"
"template_name" — "模板名称" / "Template Name"
"terminal_already_running" — "终端已在运行" / "Terminal Already Running"
"terminal_running_message" — "{name} 已在运行，选择启动方式" / "{name} is running. Choose launch mode."
"new_tab" — "新建标签页" / "New Tab"
"new_window" — "新建窗口" / "New Window"
"confirm" — "确认" / "Confirm"
"delete_template_confirm" — "确定要删除模板 {name} 吗？" / "Delete template {name}?"
```

## 不做的事情

- 不引入独立 JSON 文件存储，全部用 `@AppStorage`
- 不做模板导入/导出
- 不做模板排序（按创建顺序）
- 不做模板同步到 iCloud
- Alacritty 不支持标签页，始终新窗口
