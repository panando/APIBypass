<div align="center">

# APIBypass

<img src="APIBypass.png" alt="APIBypass" width="128">

**一个地址，接入所有模型，零折腾。**

APIBypass 是一款 macOS 菜单栏应用，充当你的本地大模型 API 网关。只需配置一次，所有 AI 客户端通过同一个地址即可接入你配置的全部模型 —— 自动格式转换、模型映射、参数注入、Claude Code 多模型启动，一站式搞定。

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

> *受够了在不同客户端和提供商之间来回配置 API Key。Claude Code 只认 Anthropic 格式，但大多数第三方模型用的是 OpenAI 格式。不同模型还需要不同的 temperature、thinking 参数。我想要一个应用搞定一切 —— 格式转换、模型映射、参数注入 —— 而且只从一个菜单栏图标管理。*
>
> *这就是我开发 APIBypass 的原因。*

## 安装

### 直接下载（推荐）

从 [Releases](https://github.com/panando/APIBypass/releases) 页面下载最新的 `.dmg` 安装包，拖入 Applications 文件夹即可。首次打开时系统会提示授予网络权限，请允许。

### 从源码编译

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass

# 调试模式运行
swift run

# 或编译 release 版本
swift build -c release
.build/arm64-apple-macosx/release/APIBypass
```

要求：macOS 14.0+、Swift 6.0+、Xcode 16.0+

## 快速开始

### 1. 启动服务

点击菜单栏的 APIBypass 图标。应用启动时服务会自动开启，状态指示灯变绿即表示正在运行，监听 `127.0.0.1:8390`（默认端口，可在设置中修改）。

### 2. 配置提供商

点击菜单栏「配置...」，创建提供商：

| 字段 | 说明 | 示例 |
|---|---|---|
| 提供商名称 | 便于识别的名称 | `我的 DeepSeek` |
| API 类型 | OpenAI 或 Anthropic | `OpenAI` |
| Base URL | 上游 API 地址 | `https://api.deepseek.com/v1` |
| API Key | 上游 API 密钥 | 存储在钥匙串中 |

API 类型决定是否需要格式转换：
- 客户端发送 Anthropic 格式但提供商是 OpenAI → 自动转换
- 客户端发送 OpenAI 格式但提供商是 Anthropic → 自动转换
- 格式相同 → 不转换，直接透传

### 3. 配置模型映射

在每个提供商下创建模型映射：

| 字段 | 说明 | 示例 |
|---|---|---|
| 配置名称 | 便于识别的名称 | `Claude Sonnet` |
| 客户端模型名 | 客户端请求的模型名 | `claude-sonnet-4-6` |
| 实际模型名 | 上游 API 的实际模型名 | `deepseek-chat` |

### 4. 启动 Claude Code

点击菜单栏「启动 Claude Code」：
1. 选择提供商（Base URL 和 API Token 自动配置）
2. 选择终端
3. 选择 `ANTHROPIC_MODEL` 对应的模型（必填）
4. 可选配置 Opus/Sonnet/Haiku/Subagent 模型默认值
5. 设置 effort level（none、low、medium、high、max）
6. 点击「启动」— Claude Code 在终端中打开，所有环境变量已设置

### 5. 配置客户端（手动）

如果不使用启动器，将 AI 客户端的 API 地址改为 `http://127.0.0.1:8390/v1`：

```
OpenAI Base URL: http://127.0.0.1:8390/v1
Anthropic Base URL: http://127.0.0.1:8390/v1
```

API Key 填写任意值（代理会替换为真实 Key）。

---

## 功能特性

### API 格式转换

自动 Anthropic ↔ OpenAI 格式转换 —— 请求体、响应、SSE 流、工具调用、思考模式。智能检测：只在客户端格式 ≠ 上游提供商格式时转换。

| 端点 | 说明 |
|---|---|
| `POST /v1/chat/completions` | OpenAI Chat Completions API |
| `POST /v1/messages` | Anthropic Messages API |
| `GET /v1/models` | 模型列表 |

### Claude Code 多模型启动器

**打破 Claude Code 的模型限制。** 一键启动 Claude Code，为 Opus、Sonnet、Haiku 等角色分别指定不同提供商的模型 —— 一次会话，多厂商模型协同工作，无缝切换。

- 终端选择：Terminal.app、iTerm2、Alacritty、Kitty、Warp、Hyper、Warple
- Effort level 选择器：none、low、medium、high、max
- **缓存修复**：去除 `cch` 计费头，控制 `CLAUDE_CODE_ATTRIBUTION_HEADER`
- **1M 上下文修复**：自动为长上下文模型追加 `[1m]` 后缀

### 模型映射与参数注入

- **模型映射**：客户端请求 `claude-sonnet-4-6`，实际调用你指定的任意模型
- **参数注入**：temperature、max tokens、top p、frequency/presence penalty
- **思考模式开关**：一键开启/关闭，兼容 Anthropic 和 OpenAI 格式
- **自定义 JSON 参数**：注入任意类型参数值

### 提供商管理

- 独立的 Provider 配置（API 类型、Base URL、API Key）
- 模型映射引用提供商 —— 无需重复配置凭证
- 每个提供商可配置环境变量，用于 Claude Code 集成
- 自动从旧格式迁移

### Codex Adaptor

内置的 Responses API 代理，专为 OpenAI Codex CLI 设计。从菜单栏「Codex Adaptor」启动，将 Codex 的 Responses API 调用转换为 Chat Completions 格式。

- **通信协议**：可选 Chat Completions 或 Responses API 线路格式
- **推理配置**：自动检测或手动配置不同提供商的 thinking/effort 参数
- **自定义模型**：定义模型别名，映射到 APIBypass 的模型配置
- **CDP 增强**：Codex Electron 应用的插件入口解锁、市场解锁和强制安装插件
- **实时日志**：内置日志查看器，支持过滤、复制、导出和清除

使用方式：启动 Codex Adaptor 服务后，将 Codex CLI 的 API 地址指向 `http://127.0.0.1:15721/v1`。

### 代理直通模式

菜单栏一键切换纯代理模式。开启后请求透明透传，不做 API 格式转换，同时保留模型映射和参数注入。

### 安全与隐私

- API Key 存储在 macOS Keychain 中，配置文件无明文密钥
- 所有流量本地处理，不经过第三方服务器
- 不收集任何遥测或使用数据

---

## 架构

```
HTTPServer (Hummingbird 2.0)
    │
    ├── /v1/chat/completions  (OpenAI Chat Completions)
    ├── /v1/messages          (Anthropic Messages)
    └── /v1/models            (模型列表)
    │
    ├── ProxyEngine
    │   ├── 请求转换（模型名 + 参数注入）
    │   └── 格式检测
    │
    ├── FormatTranslator
    │   ├── Anthropic → OpenAI 请求/响应
    │   └── OpenAI → Anthropic 请求/响应
    │
    ├── StreamTranslator
    │   ├── OpenAI SSE → Anthropic SSE
    │   └── Anthropic SSE → OpenAI SSE
    │
    ├── Rectifier
    │   ├── 思考签名自动修复
    │   └── 预算 Token 自动修复
    │
    └── KeychainService (API Key 安全存储)
```

## 设置面板

通过菜单栏「设置...」打开：

- **语言**：切换中文 / English，修改后立即生效
- **服务端口**：配置本地代理端口（默认 8390，修改后需重启服务生效）
- **关于**：版本号、项目简介、GitHub 仓库链接、MIT 许可证信息

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

---

## 给项目点个 Star

如果这个项目对你有帮助，请给个 Star 支持一下，谢谢！
