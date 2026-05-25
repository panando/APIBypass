<div align="center">

# APIBypass

<img src="APIBypass.png" alt="APIBypass" width="128">

一个运行在 macOS 菜单栏的轻量级 LLM API 代理工具。让不支持自定义参数的 AI 客户端软件也能自由控制模型行为。

</div>

## 为什么需要 APIBypass？

很多 AI 客户端不允许自定义 API 请求参数（如关闭思考模式、调整 temperature、设置 max_tokens 等）。APIBypass 在你的本地启动一个代理服务器，拦截客户端发出的 API 请求，注入你配置的参数后再转发给真正的 API 服务端。

### 典型场景

- **闭源客户端**：某些软件不支持控制思考模式等参数，通过 APIBypass 注入自定义参数（如 `enable_thinking: false`）即可覆盖默认值。适用于所有兼容 OpenAI/Anthropic 格式的 API
- **参数注入**：为所有请求统一设置 temperature、top_p 等参数，无需修改每个客户端
- **模型映射**：将客户端请求的模型名映射到实际模型名，方便切换模型而不修改客户端配置
- **多 API 格式**：同时支持 OpenAI Chat Completions 和 Anthropic Messages 两种 API 格式

## 功能

### 核心代理
- 运行在 macOS 菜单栏，不占用 Dock 空间
- 本地代理服务器，监听 `127.0.0.1:8390`（可自定义）
- 应用启动自动开启服务
- 支持 OpenAI Chat Completions API (`/v1/chat/completions`)
- 支持 Anthropic Messages API (`/v1/messages`)
- SSE 流式输出支持 — `stream: true` 时实时转发

### 模型映射
- 模型名称映射（客户端请求名 → 实际调用名）
- 支持多组配置，每组可独立启停
- 配置页面顶部独立启停开关
- 右键菜单：复制配置（含 API Key）、删除配置
- 删除确认对话框，防止误删
- 未保存变更检测，切换配置时弹出警告

### 参数注入
- Temperature、Max Tokens、Top P、Frequency Penalty、Presence Penalty
- 思考模式覆盖：一键开启/关闭，兼容 Anthropic（`thinking` 参数）和 OpenAI 兼容 API（`enable_thinking` 参数）
- 思考预算设置（Anthropic 格式）
- 自定义 JSON 参数注入 — 支持字符串、数字、布尔、对象、数组等任意类型

### 安全与隐私
- API Key 安全存储在 macOS Keychain 中（统一的合并存储）
- 所有配置仅需一次 Keychain 授权
- 所有流量在本地处理，不经过任何第三方服务器
- 不收集任何遥测或使用数据

### 界面与体验
- 双语界面：中文 / English，在设置面板中即时切换
- 保存按钮在检测到变更时绿色高亮
- 终端实时显示格式化 JSON 请求日志
- 设置面板包含关于信息、版本号、GitHub 链接（可点击打开）和许可证信息

![配置界面](screenshot_configure.png)

![设置界面](screenshot_settings.png)

## 系统要求

- macOS 14.0 或更高版本

## 安装

### 直接下载（推荐）

从 [Releases](https://github.com/panando/APIBypass/releases) 页面下载最新的 DMG 安装包，双击挂载后将 APIBypass 拖入 Applications 文件夹即可。首次打开时系统会提示授予网络权限，请允许。

### 从源码编译

编译要求：Swift 6.0+ / Xcode 16.0+（或仅安装 Command Line Tools）

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass

# 调试模式运行
swift run

# 或编译 release 版本
swift build -c release
.build/arm64-apple-macosx/release/APIBypass
```

首次运行时，系统会提示授予网络权限，请允许。

## 使用说明

### 1. 启动服务

点击菜单栏的 APIBypass 图标。应用启动时服务会自动开启，状态指示灯变绿即表示正在运行，监听 `127.0.0.1:8390`（默认端口，可在设置中修改）。也可通过菜单栏手动启停。

### 2. 配置映射

点击菜单栏「配置...」，在配置窗口中创建模型映射：

| 字段 | 说明 | 示例 |
|------|------|------|
| 配置名称 | 便于识别的名称 | `我的自定义配置` |
| 客户端模型名 | 客户端请求的模型名 | `qwen3.6-plus` |
| 实际模型名 | 上游 API 的实际模型名 | `qwen3.6-plus` |
| API接口类型 | OpenAI 或 Anthropic | `OpenAI` |
| Base URL | 上游 API 地址 | `https://api.example.com/v1` |
| API Key | 上游 API 密钥 | 存储在钥匙串中 |

配置页面顶部的启停开关控制该映射是否生效。

### 3. 参数注入

- **更改默认推理模式**：打开总开关后可控制思考模式
  - 启用 → 注入 `enable_thinking: true`（OpenAI）或 `thinking: {type: "enabled"}`（Anthropic）
  - 禁用 → 注入 `enable_thinking: false` 或 `thinking: {type: "disabled"}`
  - 关闭总开关 → 不干预，使用 API 默认行为
- **标准参数**：填入 Temperature、Max Tokens、Top P、Frequency Penalty、Presence Penalty 即可注入
- **自定义参数**：可注入任意 JSON 字段，值自动识别类型：`"true"/"false"` → 布尔值、`"42"` → 整数、`"3.14"` → 浮点数、`"{\"key\":\"val\"}"` → JSON 对象

### 4. 配置客户端

将 AI 客户端的 API 地址改为 `http://127.0.0.1:8390/v1`，API Key 填写任意值（代理会替换为真实 Key）。

**Cursor 示例：**
```
OpenAI Base URL: http://127.0.0.1:8390/v1
Anthropic Base URL: http://127.0.0.1:8390/v1
```

### 5. 验证生效（开发者）

使用 `swift run` 运行时，在终端查看格式化请求日志：
- 原始请求体
- 上游 URL 和实际模型名
- 转换后的请求体（含注入的参数）

> 此步骤仅适用于开发者，直接下载 DMG 安装的用户不会看到终端输出。

## 设置面板

通过菜单栏「设置...」打开。设置面板提供：

- **语言**：切换中文 / English，修改后立即生效
- **服务端口**：配置本地代理端口（默认 8390，修改后需重启服务生效）
- **关于**：版本号、项目简介、GitHub 仓库链接（可点击跳转）、MIT 许可证信息

## 项目结构

```
APIBypass/
├── APIBypassApp.swift          # 应用入口 + 菜单栏图标
├── Core/
│   ├── ConfigManager.swift     # 配置管理（UserDefaults 持久化）
│   ├── HTTPServer.swift        # Hummingbird HTTP 服务器 + SSE 流式
│   ├── LocalizationManager.swift  # 国际化：中英文切换
│   └── ProxyEngine.swift       # 请求转换引擎（参数注入）
├── Models/
│   ├── APIProvider.swift       # API 提供商枚举
│   └── ModelMapping.swift      # 数据模型
├── Services/
│   ├── KeychainService.swift   # Keychain 安全存储（带缓存）
│   └── NetworkService.swift    # HTTP + 流式网络请求服务
├── UI/
│   ├── ConfigWindow.swift      # 配置窗口 + 新建映射弹窗
│   ├── MenuBarView.swift       # 菜单栏下拉视图
│   ├── SettingsView.swift      # 设置面板（语言 + 端口 + 关于）
│   └── Views/
│       ├── MappingDetailView.swift  # 配置详情编辑器
│       └── MappingListView.swift    # 配置列表（右键菜单）
└── Package.swift               # Swift Package 配置
```

## 技术栈

- **SwiftUI** — macOS 菜单栏应用 + 窗口管理
- **Hummingbird 2.0** — HTTP 服务器框架
- **Keychain Services** — API Key 安全存储（带内存缓存）
- **UserDefaults** — 配置 + 语言偏好持久化
- **async/await** — 异步网络操作（含 SSE 流式）
- **ServiceLifecycle** — 服务生命周期管理

## 隐私

- API Key 存储在系统钥匙串中，不上传到任何地方
- 所有流量在本地处理，不经过任何第三方服务器
- 不收集任何遥测或使用数据

## License

MIT
