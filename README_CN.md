<div align="center">

# APIBypass

<img src="APIBypass.png" alt="APIBypass" width="128">

**用 Claude Code 调用 DeepSeek。用 ChatGPT 应用跑 Qwen。一个本地代理，任意模型，零烦恼。**

APIBypass 是一款 macOS 菜单栏应用，让你用任意 AI 工具连接任意模型提供商。Claude Code 接 DeepSeek？ChatGPT 应用跑 Qwen？Cursor 用 GLM？只需配置一次，所有工具都能用你选的提供商 —— 不用逐个配置。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)](https://github.com/panando/APIBypass)
[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org)

[安装](#安装) ·
[快速开始](#快速开始) ·
[功能特性](#功能特性) ·
[架构](#架构) ·
[设置面板](#设置面板)

[English](./README.md) ·
**简体中文**

</div>

---

<p align="center">
  <a href="menu.png"><img src="menu.png" alt="APIBypass 菜单栏状态指示" width="400"></a>
</p>


### 为什么用 APIBypass？

你想用 Claude Code，但它只支持 Anthropic 的模型。你想用 ChatGPT 应用，但它被锁定在 OpenAI。你想试试 Cursor，结果又要配置一套新的 API Key。每次换工具，都要从头配置。

APIBypass 在网络层解决这个问题 —— 一个本地地址，所有工具都配好：

- **格式兼容** — Claude Code 说 Anthropic 格式。大多数模型说 OpenAI 格式。APIBypass 自动翻译，让你的工具直接对接任意提供商。无需改代码、打补丁、装插件。

- **一套配置通用** — 在 APIBypass 里配置一次提供商。Claude Code、Cursor、ChatGPT 应用或其他兼容 OpenAI 的工具，指向同一个本地地址就行。换工具？不用重新配置。

- **凭据保护** — 你的真实 API Key 不会离开本机。应用只能看到一个本地地址和一个占位 Key。真实凭据存在 macOS 钥匙串里，安全私密。

- **解锁 ChatGPT / Codex 应用** — ChatGPT 桌面应用（原 Codex）使用新的 API 格式，大多数代理不支持。APIBypass 填补了这个空白，让你能用 ChatGPT 应用连接 DeepSeek、Qwen、GLM 等任意提供商 —— 不限于 OpenAI。

- **Claude Code 多模型启动器** — 为 Claude Code 的 Opus、Sonnet、Haiku、Subagent 角色分别指定模型。一键启动，终端自动配好所有环境变量。

- **模型映射与参数注入** — 客户端请求 `gpt-4`，APIBypass 路由到 `deepseek-chat`。为每个模型设置 temperature、thinking 模式、自定义参数 —— 每次请求自动应用。

## 安装

### 直接下载（推荐）

从 [Releases](https://github.com/panando/APIBypass/releases) 下载最新 `.dmg`，并将 APIBypass 拖入 Applications。首次启动时允许网络连接。

### macOS 提示“已损坏，无法打开”的处理方法

当前 Release 版本使用 ad-hoc 签名，尚未使用 Apple Developer ID 证书签名，也没有经过 Apple notarization。因此，从 GitHub 或浏览器下载后，macOS Gatekeeper 可能会提示：

> “APIBypass”已损坏，无法打开。你应该将它移到废纸篓。

这通常不是应用真的损坏，而是 macOS 给下载的未 notarized 应用添加了 quarantine 隔离标记。

#### 方法一：通过系统设置打开

1. 双击打开 APIBypass。
2. 如果 macOS 阻止打开，进入系统设置 → 隐私与安全性。
3. 在“安全性”区域找到 APIBypass 的拦截提示。
4. 点击“仍要打开”或“Open Anyway”。
5. 再次确认打开。

#### 方法二：使用 Terminal 修复

如果系统设置里没有出现“仍要打开”，或者仍然提示“已损坏”，请先把 APIBypass 拖到 Applications 文件夹，然后打开 Terminal，运行：

```bash
sudo xattr -dr com.apple.quarantine /Applications/APIBypass.app
```

输入你的 Mac 登录密码后按 Enter。Terminal 输入密码时不会显示字符，这是正常的。然后重新打开 APIBypass。

如果你不确定应用路径，可以先输入下面这行命令，注意最后有一个空格：

```bash
sudo xattr -dr com.apple.quarantine 
```

然后从 Finder 把 `APIBypass.app` 拖进 Terminal 窗口，再按 Enter。

> 注意：请只对你信任来源的应用执行这个操作。未来如果项目获得 Apple Developer ID 证书，将提供正式签名并 notarized 的版本，届时无需执行上述步骤。

### 从源码编译

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
swift run      # 调试模式
# 或
swift build -c release && .build/arm64-apple-macosx/release/APIBypass
```

要求 macOS 14.0+、Swift 6.0+、Xcode 16.0+。

## 快速开始

### 1. 启动服务

点击菜单栏 APIBypass 图标，服务自动启动于 `127.0.0.1:8390`。绿色指示灯 = 运行中。

### 2. 添加提供商

菜单栏 →「配置 APIBypass」→ 创建提供商：

<p align="center">
  <a href="screenshot_apibypass_configure.png"><img src="screenshot_apibypass_configure.png" alt="提供商与模型映射配置" width="720"></a>
</p>

| 字段 | 说明 | 示例 |
|---|---|---|
| 提供商名称 | 便于识别 | `我的 DeepSeek` |
| API 类型 | OpenAI 或 Anthropic | `OpenAI` |
| Base URL | 上游 API 地址 | `https://api.deepseek.com/v1` |
| API Key | 上游密钥 | 存储在钥匙串中 |

### 3. 添加模型映射

在每个提供商下创建映射：

| 字段 | 说明 | 示例 |
|---|---|---|
| 客户端模型名 | 客户端发送的模型名 | `claude-sonnet-4-6` |
| 实际模型名 | 上游 API 需要的模型名 | `deepseek-chat` |

### 4. 配置客户端

将 AI 工具的 Base URL 设为 `http://127.0.0.1:8390/v1`。API Key 可以随便填 —— APIBypass 会替换为真实密钥。

### 5. 启动 Claude Code（可选）

菜单栏 →「启动 Claude Code」：

<p align="center">
  <a href="screenshot_launch_claude_code.png"><img src="screenshot_launch_claude_code.png" alt="启动 Claude Code 配置" width="720"></a>
</p>

1. 选择提供商（Base URL 和 Token 自动配置）
2. 选择终端
3. 为 Anthropic/Opus/Sonnet/Haiku/Subagent 选择模型
4. 设置 effort level
5. 点击「启动」

Claude Code 在终端中打开，所有环境变量已配好，每个模型角色通过你指定的提供商路由。

### 6. 启动 ChatGPT / Codex（可选）

菜单栏 →「启动 Codex」：

> **说明**：ChatGPT 桌面应用原名为 "Codex"。APIBypass 同时支持新版 ChatGPT 应用和旧版 Codex 应用 —— 菜单项「启动 Codex」对两者都适用。

<p align="center">
  <a href="screenshot_launch_codex.png"><img src="screenshot_launch_codex.png" alt="启动 Codex 配置" width="720"></a>
</p>

1. Codex 适配服务自动启动（如未运行）
2. Codex 应用以配置的调试端口启动
3. 将 Codex 指向 `http://127.0.0.1:15721/v1`

---

## 功能特性

### Anthropic ↔ OpenAI 格式转换

**核心能力。** 请求体、响应体、SSE 事件流、工具调用、thinking/redacted_thinking 块的全双向转换。智能检测：只在客户端格式 ≠ 提供商格式时才转换。

| 端点 | 说明 |
|---|---|
| `POST /v1/chat/completions` | OpenAI Chat Completions |
| `POST /v1/messages` | Anthropic Messages |
| `GET /v1/models` | 模型列表 |

### Claude Code 多模型启动器

**打破 Claude Code 的单模型限制。** 为 Opus、Sonnet、Haiku、Subagent 每个角色指定不同的上游模型，一次会话多模型协同。

- 7 种终端：Terminal.app、iTerm2、Alacritty、Kitty、Warp、Hyper、Warple
- Effort level 选择器（none → max）
- 缓存修复：去除 `cch` 计费头，控制 `CLAUDE_CODE_ATTRIBUTION_HEADER`
- 1M 上下文修复：自动为长上下文模型追加 `[1m]` 后缀
- 启动模板：保存和切换模型配置组合

### ChatGPT / Codex 应用支持 —— 任意提供商，不限于 OpenAI

ChatGPT 桌面应用（原 Codex）和旧版 Codex 应用使用新的 **Responses API** 格式，几乎没有代理支持。APIBypass 是首个填补这一空白的 macOS 工具：实时将 Responses API ↔ Chat Completions 互转，并通过模型映射和参数注入处理请求。结果：**ChatGPT / Codex 可以使用任意提供商的任意模型** —— DeepSeek、Qwen、GLM、MiniMax，而不仅限于 OpenAI。

<p align="center">
  <a href="screenshot_codexadaptor_configure.png"><img src="screenshot_codexadaptor_configure.png" alt="Codex Adaptor 配置" width="720"></a>
</p>

```
Codex ──Responses API──▶ Codex Adaptor (:15721) ──Chat Completions──▶ APIBypass (:8390) ──▶ 上游
```

**线路协议** — 选择 Chat Completions 或 Responses API 作为暴露的线路格式，附带场景化选择指引。

**推理配置** — 自动检测或手动配置各提供商的 thinking/effort 参数。支持 DeepSeek（`thinking`）、OpenRouter（`reasoning_effort`）、SiliconFlow（`thinking`）、MiniMax（`thinking`）、Qwen（`enable_thinking`）等 —— 每种均可配置预算 token 和 effort 等级。

**自定义模型** — 定义显示名称别名，映射到 APIBypass 的模型配置，支持自定义上下文窗口。模型自动同步到 `~/.codex/providers.json` 供 Codex 使用。

**CDP 增强** — Codex Electron 应用暴露出 Chrome DevTools Protocol 调试端口。APIBypass 连接该端口并注入 JavaScript 来解锁隐藏能力：
- 强制入口解锁 — 绕过等待列表/登录限制
- 插件市场解锁 — 直接访问插件市场
- 强制安装插件 — 无限制安装任意插件
- 设置通过 WebSocket 实时推送，无需重启即可生效

**实时日志** — 线程安全的环形缓冲区（2000 条），通过定时器轮询显示。支持按级别过滤、复制全部、导出文件、清空。不使用 `@Published`/Combine —— 避免后台线程 AutoLayout 崩溃。

**配置自动恢复** — UserDefaults 被清除后，下次启动自动从 `~/.codex/providers.json` 恢复线路协议、推理配置和自定义模型。

从菜单栏「Codex Adaptor」启动，将 Codex 指向 `http://127.0.0.1:15721/v1`。

### 模型映射与参数注入

- **模型别名**：任意客户端模型名 → 任意上游实际模型
- **按映射注入参数**：temperature、max_tokens、top_p、frequency_penalty、presence_penalty
- **思考模式开关**：一键开启/关闭，兼容 Anthropic 和 OpenAI 格式
- **自定义 JSON 注入**：注入任意参数，自动类型识别（bool、int、float、JSON、string）
- **本地模型参数清理**：转发到云端 API 前自动去除 Ollama/LM Studio 专用参数

### 提供商管理

- 独立提供商配置（API 类型、Base URL、API Key），多个映射共享
- 每个提供商可配置环境变量，支持手动、模型映射、钥匙串、Base URL 四种类型
- 从旧版格式自动迁移

### 代理直通模式

一键切换纯代理模式 —— 请求透明透传，不做格式转换，保留模型映射和参数注入。

### 安全

- API Key 在 macOS 钥匙串中加密存储，绝不明文落盘
- 所有流量本地处理，无云端中转，无遥测
- 开源，MIT 协议

---

## 架构

```
ChatGPT / Codex ──▶ Codex Adaptor (:15721) ──▶┐
                                         │
客户端 (Claude Code / Cursor / 任意工具)  │
    │                                    │
    ▼                                    │
┌────────────────────────────────────────▼┐
│  HTTPServer (Hummingbird 2.0)           │
│  :8390                                  │
│                                          │
│  POST /v1/chat/completions              │
│  POST /v1/messages                      │
│  GET  /v1/models                        │
└──────────────┬──────────────────────────┘
               │
       ┌───────┴────────┐
       ▼                ▼
┌─────────────┐  ┌──────────────────┐
│ ProxyEngine │  │ FormatTranslator │
│ • 模型映射  │  │ • 请求 → 请求   │
│ • 参数注入  │  │ • 响应 → 响应   │
│ • 去本地参数│  │StreamTranslator │
└──────┬──────┘  │ • SSE ↔ SSE     │
       │         │Rectifier        │
       │         │ • thinking 修复 │
       │         │ • budget 修复   │
       │         └────────┬─────────┘
       │                  │
       ▼                  ▼
┌─────────────────────────────────┐
│  上游提供商 (OpenAI / Anthropic  │
│  / DeepSeek / 等)               │
└─────────────────────────────────┘
```

---

## 设置面板

菜单栏 →「设置...」：

<p align="center">
  <a href="screenshot_settings.png"><img src="screenshot_settings.png" alt="APIBypass 设置窗口" width="500"></a>
</p>

- **语言**：中文 / English，即时生效
- **服务端口**：默认 8390，修改后重启生效
- **追踪日志**：开启请求/响应日志用于调试

菜单栏 →「关于」：

<p align="center">
  <a href="screenshot_about.png"><img src="screenshot_about.png" alt="关于 APIBypass" width="320"></a>
</p>

## 技术栈

- **SwiftUI** — macOS 菜单栏应用 + 窗口管理
- **Hummingbird 2.0** — HTTP 服务器
- **Keychain Services** — API Key 安全存储（带缓存）
- **async/await** — 异步网络（含 SSE 流式）
- **ServiceLifecycle** — 服务生命周期管理

---

## 参与贡献

欢迎各种形式的贡献 —— Bug 反馈、功能建议、UI/UX 优化、翻译、代码修复都能帮到项目。

- **Bug 与功能建议**：提一个 [issue](../../issues)，写清问题描述和复现步骤。
- **Pull Request**：fork 仓库，新建分支，向 `main` 提 PR。改动尽量聚焦，并在 PR 描述里说明意图。
- **翻译**：应用通过 `LocalizationManager` 做本地化，新增或改进语言是很好的入门贡献。
- **讨论**：提 PR 前想先聊聊思路，可以开一个 [discussion](../../discussions)。

请保持友善、建设性的交流。提交贡献即表示你同意按项目许可证授权你的贡献内容。

---

## 给项目点个 Star

如果 APIBypass 帮你省了时间，请给个 Star —— 让更多人看到这个项目。
