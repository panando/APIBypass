<div align="center">

# APIBypass

<img src="APIBypass.png" alt="APIBypass" width="128">

**One BaseURL. All models. Zero hassle.**

APIBypass is a macOS menu bar app that acts as your local LLM API gateway. Configure once, and every AI client connects to all your models through a single address — automatic format translation, model mapping, parameter injection, and Claude Code multi-model launch, all in one place.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)](https://github.com/panando/APIBypass)
[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org)

[Install](#install) ·
[Quickstart](#quickstart) ·
[Features](#features) ·
[Architecture](#architecture) ·
[Settings](#settings)

**English** ·
[简体中文](./README_CN.md)

</div>

---

[![menu](menu.png)](menu.png)

[![Configure](screenshot_configure.png)](screenshot_configure.png)

> *I was tired of juggling API keys across different clients and providers. Claude Code only speaks Anthropic format, but most third-party models use OpenAI format. Different models need different temperature and thinking settings. I wanted one app that handles everything — format translation, model mapping, parameter injection — from a single menu bar icon.*
>
> *That's why I built APIBypass.*

## Install

### Download (Recommended)

Download the latest `.dmg` from [Releases](https://github.com/panando/APIBypass/releases), drag to Applications, done. On first launch, allow network connections when prompted.

### Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass

# Run in debug mode
swift run

# Or build release binary
swift build -c release
.build/arm64-apple-macosx/release/APIBypass
```

Requires macOS 14.0+, Swift 6.0+, Xcode 16.0+.

## Quickstart

### 1. Start the Server

Click the APIBypass icon in the menu bar. The server starts automatically on launch, and the indicator turns green when running on `127.0.0.1:8390` (default port, configurable in Settings).

### 2. Configure Providers

Click "Configure..." in the menu bar. Create a provider:

| Field | Description | Example |
|---|---|---|
| Provider Name | A label for this provider | `My DeepSeek` |
| API Provider | OpenAI or Anthropic | `OpenAI` |
| Base URL | Upstream API endpoint | `https://api.deepseek.com/v1` |
| API Key | Your upstream API key | Stored in Keychain |

The API Provider type determines whether format translation is needed:
- If client sends Anthropic format but provider is OpenAI → automatic translation
- If client sends OpenAI format but provider is Anthropic → automatic translation
- Same format → no translation, direct passthrough

### 3. Configure Model Mappings

Inside each provider, create model mappings:

| Field | Description | Example |
|---|---|---|
| Config Name | A label for this mapping | `Claude Sonnet` |
| Incoming Model | The model name your client sends | `claude-sonnet-4-6` |
| Actual Model | The real model to call upstream | `deepseek-chat` |

### 4. Launch Claude Code

Click "Launch Claude Code" in the menu bar:
1. Select a provider (base URL and API token are auto-configured)
2. Select your preferred terminal
3. Choose a model for `ANTHROPIC_MODEL` (required)
4. Optionally configure Opus/Sonnet/Haiku/Subagent model defaults
5. Set effort level (none, low, medium, high, max)
6. Click "Launch" — Claude Code opens in your terminal with all environment variables set

### 5. Configure Your Client (Manual)

If not using the launcher, point your AI client to `http://127.0.0.1:8390/v1`:

```
OpenAI Base URL: http://127.0.0.1:8390/v1
Anthropic Base URL: http://127.0.0.1:8390/v1
```

The API Key field can be anything — the proxy replaces it with your real key.

---

## Features

### API Format Translation

Automatic Anthropic ↔ OpenAI format translation — request bodies, responses, SSE streams, tool calls, thinking mode. Smart detection: only translates when client format ≠ upstream provider format.

| Endpoint | Description |
| --- | --- |
| `POST /v1/chat/completions` | OpenAI Chat Completions API |
| `POST /v1/messages` | Anthropic Messages API |
| `GET /v1/models` | List available models |

### Claude Code Multi-Model Launcher

**Break Claude Code's model barrier.** Launch Claude Code with one click and assign different providers to Opus, Sonnet, Haiku, and other roles — one session, multiple providers working together seamlessly.

- Terminal selection: Terminal.app, iTerm2, Alacritty, Kitty, Warp, Hyper, Warple
- Effort level selector: none, low, medium, high, max
- **Cache fix**: strips `cch` billing headers, controls `CLAUDE_CODE_ATTRIBUTION_HEADER`
- **1M context fix**: auto-appends `[1m]` suffix for long-context models

### Model Mapping & Parameter Injection

- **Model mapping**: your client requests `claude-sonnet-4-6`, APIBypass calls whatever model you specify
- **Parameter injection**: temperature, max tokens, top p, frequency/presence penalty
- **Thinking mode toggle**: one-click on/off, compatible with both Anthropic and OpenAI formats
- **Custom JSON fields**: inject any parameter with any value type

### Provider Management

- Separate Provider configurations (API type, base URL, API key)
- Model mappings reference providers — no duplicate credentials
- Environment variables per provider for Claude Code integration
- Auto-migration from legacy format

### Bypass Mode

One-click toggle in the menu bar to enable pure proxy mode. When activated, requests pass through transparently without API format conversion, while still preserving model mapping and parameter injection.

### Security & Privacy

- API Keys stored in macOS Keychain — single authorization, no plaintext in config files
- All traffic processed locally — no third-party servers involved
- No telemetry or usage data collected

---

## Architecture

```
HTTPServer (Hummingbird 2.0)
    │
    ├── /v1/chat/completions  (OpenAI Chat Completions)
    ├── /v1/messages          (Anthropic Messages)
    └── /v1/models            (Model listing)
    │
    ├── ProxyEngine
    │   ├── Request transform (model name + parameter injection)
    │   └── Format detection
    │
    ├── FormatTranslator
    │   ├── Anthropic → OpenAI request/response
    │   └── OpenAI → Anthropic request/response
    │
    ├── StreamTranslator
    │   ├── OpenAI SSE → Anthropic SSE
    │   └── Anthropic SSE → OpenAI SSE
    │
    ├── Rectifier
    │   ├── Thinking signature auto-fix
    │   └── Budget token auto-fix
    │
    └── KeychainService (API key secure storage)
```

## Settings

Access via menu bar "Settings...":

- **Language**: Switch between Chinese (中文) and English — takes effect immediately
- **Server Port**: Configure the local proxy port (default 8390, restart required to apply)
- **About**: Version number, project description, GitHub repository link, and MIT License info

## Tech Stack

- **SwiftUI** — macOS menu bar app + windows
- **Hummingbird 2.0** — HTTP server framework
- **Keychain Services** — API key secure storage with caching
- **UserDefaults** — Config + language persistence
- **async/await** — Async networking (including SSE streaming)
- **ServiceLifecycle** — Service lifecycle management

## Privacy

- API Keys are stored in the system Keychain and never uploaded anywhere
- All traffic is processed locally — no third-party servers involved
- No telemetry or usage data collected

---

## Star this project

Your support means a lot — please star this project if you find it useful.
