<div align="center">

# APIBypass

<img src="APIBypass.png" alt="APIBypass" width="128">

**任意客户端。任意模型。任意格式。一个地址。**

APIBypass 是一款 macOS 菜单栏应用，位于你的 AI 工具与上游 API 提供商之间 —— 自动转换 API 格式、重映射模型名称、注入参数配置、一键启动多模型 Claude Code。只配置一次，所有工具通用。

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

[![菜单栏](menu.png)](menu.png)

[![配置界面](screenshot_configure.png)](screenshot_configure.png)

### 为什么用 APIBypass？

Claude Code 只认 Anthropic 格式。大多数第三方模型说的是 OpenAI 格式。不同模型需要不同的 temperature、thinking 预算和上下文长度。切换提供商通常意味着重新配置每一个客户端。

APIBypass 在网络层解决所有这些问题 —— 一个本地地址，客户端零改动：

- **格式转换** — Anthropic ↔ OpenAI 双向互转，包括 SSE 流式、工具调用、思考模式。只在格式不匹配时才转换。
- **模型映射** — 客户端请求 `claude-sonnet-4-6`，APIBypass 路由到你指定的任意模型。
- **参数注入** — temperature、top-p、thinking 模式、自定义 JSON 参数 —— 每个模型设置一次，每次请求自动生效。
- **Claude Code 启动器** — 为 Opus、Sonnet、Haiku、Subagent 分别指定不同的上游模型。一键启动，一个终端，全部配齐。
- **Codex Adaptor** — 内置 Responses API 代理，支持 Codex CLI，附带 CDP 注入增强 Codex Electron。
- **钥匙串安全** — API Key 存储在 macOS 钥匙串中，绝不明文落盘。所有流量仅在本地处理。

## 安装

### 直接下载（推荐）

从 [Releases](https://github.com/panando/APIBypass/releases) 下载最新 `.dmg`，拖入 Applications 即可。首次启动时允许网络连接。

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

菜单栏 →「配置...」→ 创建提供商：

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
1. 选择提供商（Base URL 和 Token 自动配置）
2. 选择终端
3. 为 Anthropic/Opus/Sonnet/Haiku/Subagent 选择模型
4. 设置 effort level
5. 点击「启动」

Claude Code 在终端中打开，所有环境变量已配好，每个模型角色通过你指定的提供商路由。

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

### Codex Adaptor

内置 [OpenAI Codex CLI](https://github.com/openai/codex) 代理。将 Codex 的 Responses API 调用转换为 Chat Completions，经 APIBypass 路由实现模型映射和参数注入。

- **线路协议**：Chat Completions 或 Responses API
- **推理配置**：自动检测或手动配置 thinking/effort（支持 DeepSeek、OpenRouter、SiliconFlow、MiniMax、Qwen 等）
- **自定义模型**：定义显示名称，映射到 APIBypass 模型配置
- **CDP 增强**：强制解锁入口、插件市场解锁、强制安装插件（Codex Electron）
- **实时日志**：过滤、复制、导出、清空
- **自动恢复**：UserDefaults 丢失时从 `~/.codex/providers.json` 自动恢复配置

从菜单栏「Codex Adaptor」启动，将 Codex CLI 指向 `http://127.0.0.1:15721/v1`。

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
客户端 (Claude Code / Cursor / 任意工具)
    │
    ▼
┌─────────────────────────────────────────┐
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

- **语言**：中文 / English，即时生效
- **服务端口**：默认 8390，修改后重启生效
- **关于**：版本号、项目简介、GitHub 链接、MIT 许可证

## 技术栈

- **SwiftUI** — macOS 菜单栏应用 + 窗口管理
- **Hummingbird 2.0** — HTTP 服务器
- **Keychain Services** — API Key 安全存储（带缓存）
- **async/await** — 异步网络（含 SSE 流式）
- **ServiceLifecycle** — 服务生命周期管理

---

## 给项目点个 Star

如果 APIBypass 帮你省了时间，请给个 Star —— 让更多人看到这个项目。
