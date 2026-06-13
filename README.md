<div align="center">

# APIBypass

<img src="APIBypass.png" alt="APIBypass" width="128">

**Any AI client. Any model. Any format. One endpoint.**

APIBypass is a macOS menu bar app that sits between your AI tools and upstream API providers — translating formats, remapping model names, injecting parameters, and launching Claude Code with multi-model routing. Configure once, use everywhere.

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

### Why APIBypass?

Claude Code speaks Anthropic. Most models speak OpenAI. Different models need different temperatures, thinking budgets, and context limits. Switching providers usually means reconfiguring every client.

APIBypass solves all of this at the network layer — one local endpoint, zero client changes:

- **Format translation** — Anthropic ↔ OpenAI in both directions, including SSE streaming, tool calls, and thinking mode. Only translates when formats don't match.
- **Model mapping** — your client asks for `claude-sonnet-4-6`, APIBypass routes it to any model you choose.
- **Parameter injection** — temperature, top-p, thinking mode, custom JSON fields — set once per model, applied to every request.
- **Claude Code launcher** — assign different providers to Opus, Sonnet, Haiku, and Subagent roles. One click, one terminal, all models.
- **Codex Adaptor** — built-in Responses API proxy for Codex CLI, with CDP injection for the Codex Electron app.
- **Keychain security** — API keys in macOS Keychain, never in plaintext. All traffic stays on your machine.

## Install

### Download (Recommended)

Download the latest `.dmg` from [Releases](https://github.com/panando/APIBypass/releases), drag to Applications, done. On first launch, allow network connections when prompted.

### Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
swift run      # debug mode
# or
swift build -c release && .build/arm64-apple-macosx/release/APIBypass
```

Requires macOS 14.0+, Swift 6.0+, Xcode 16.0+.

## Quickstart

### 1. Start the Server

Click the APIBypass icon in the menu bar — the server auto-starts on `127.0.0.1:8390`. Green dot = running.

### 2. Add a Provider

Menu bar → "Configure..." → create a provider:

| Field | Description | Example |
|---|---|---|
| Provider Name | A label | `My DeepSeek` |
| API Provider | OpenAI or Anthropic | `OpenAI` |
| Base URL | Upstream API endpoint | `https://api.deepseek.com/v1` |
| API Key | Your upstream key | Stored in Keychain |

### 3. Add Model Mappings

Inside each provider, create mappings:

| Field | Description | Example |
|---|---|---|
| Incoming Model | What your client sends | `claude-sonnet-4-6` |
| Actual Model | What the upstream expects | `deepseek-chat` |

### 4. Point Your Client

Set your AI client's base URL to `http://127.0.0.1:8390/v1`. The API Key field can be anything — APIBypass replaces it with your real key.

### 5. Launch Claude Code (Optional)

Menu bar → "Launch Claude Code":
1. Pick a provider (base URL and token auto-configured)
2. Choose a terminal
3. Select models for Anthropic/Opus/Sonnet/Haiku/Subagent roles
4. Set effort level
5. Click "Launch"

Claude Code opens with all environment variables set, routing each model role through your chosen provider.

---

## Features

### Anthropic ↔ OpenAI Format Translation

**The core superpower.** Full bidirectional translation of request bodies, responses, SSE event streams, tool calls, and thinking/redacted_thinking blocks. Smart detection: only translates when the client format ≠ provider format.

| Endpoint | Description |
|---|---|
| `POST /v1/chat/completions` | OpenAI Chat Completions |
| `POST /v1/messages` | Anthropic Messages |
| `GET /v1/models` | Model listing |

### Claude Code Multi-Model Launcher

**Break Claude Code's single-model limitation.** Assign different upstream models to each Claude Code role — Opus, Sonnet, Haiku, and Subagent — all in one session.

- 7 terminal options: Terminal.app, iTerm2, Alacritty, Kitty, Warp, Hyper, Warple
- Effort level selector (none → max)
- Cache fix: strips `cch` billing headers, controls `CLAUDE_CODE_ATTRIBUTION_HEADER`
- 1M context fix: auto-appends `[1m]` suffix for long-context models
- Launch templates: save and switch between model configurations

### Codex Adaptor

Built-in proxy for [OpenAI Codex CLI](https://github.com/openai/codex). Translates Codex's Responses API calls to Chat Completions, routing through APIBypass for model mapping and parameter injection.

- **Wire protocol**: Chat Completions or Responses API
- **Reasoning config**: Auto-detect or manual thinking/effort per provider (DeepSeek, OpenRouter, SiliconFlow, MiniMax, Qwen, etc.)
- **Custom models**: Define display names mapped to APIBypass model mappings
- **CDP Enhancements**: Force entry unlock, plugin marketplace unlock, force plugin install for Codex Electron
- **Real-time logs**: Filter, copy, export, clear
- **Auto-recovery**: Recovers config from `~/.codex/providers.json` if UserDefaults is cleared

Start from menu bar "Codex Adaptor", point Codex CLI to `http://127.0.0.1:15721/v1`.

### Model Mapping & Parameter Injection

- **Model aliasing**: Any incoming model name → any actual upstream model
- **Parameter injection per mapping**: temperature, max_tokens, top_p, frequency_penalty, presence_penalty
- **Thinking mode toggle**: one-click on/off, compatible with both Anthropic and OpenAI formats
- **Custom JSON injection**: inject arbitrary parameters with automatic type detection (bool, int, float, JSON, string)
- **Local model cleanup**: strips Ollama/LM Studio-specific params before forwarding to cloud APIs

### Provider Management

- Independent provider configs (API type, base URL, API key) — reuse across mappings
- Environment variables per provider for Claude Code integration (manual, model-mapping, keychain, base-url types)
- Auto-migration from legacy format

### Bypass Mode

One-click toggle for pure proxy mode — requests pass through without format translation, keeping model mapping and parameter injection active.

### Security

- API keys in macOS Keychain, never plaintext on disk
- All traffic processed locally — no cloud relay, no telemetry
- Open source, MIT licensed

---

## Architecture

```
Client (Claude Code / Cursor / Anything)
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
│ • model map │  │ • req → req      │
│ • param inj │  │ • resp → resp    │
│ • strip loc │  │StreamTranslator  │
└──────┬──────┘  │ • SSE ↔ SSE      │
       │         │Rectifier         │
       │         │ • thinking fix   │
       │         │ • budget fix     │
       │         └────────┬─────────┘
       │                  │
       ▼                  ▼
┌─────────────────────────────────┐
│  Upstream Provider (OpenAI /    │
│  Anthropic / DeepSeek / etc.)   │
└─────────────────────────────────┘
```

---

## Settings

Menu bar → "Settings...":

- **Language**: 中文 / English, takes effect immediately
- **Server Port**: Default 8390, restart to apply
- **About**: Version, description, GitHub link, MIT license

## Tech Stack

- **SwiftUI** — macOS menu bar app + windows
- **Hummingbird 2.0** — HTTP server
- **Keychain Services** — API key storage with caching
- **async/await** — networking including SSE streaming
- **ServiceLifecycle** — service lifecycle management

---

## Star This Project

If APIBypass saves you time, please star the repo — it helps others find it too.
