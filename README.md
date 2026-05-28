<div align="center">

# APIBypass

<img src="APIBypass.png" alt="APIBypass" width="128">

**APIBypass** is a macOS menu bar app that acts as a local LLM API proxy with automatic format translation. It bridges incompatible API formats (Anthropic ↔ OpenAI), injects custom parameters, maps model names, and centrally manages your AI provider configurations — all without modifying your clients.

[中文说明](README_CN.md)

</div>

## Why APIBypass?

Many AI clients don't let you customize API request parameters, and some clients (like Claude Code) only support specific API formats. APIBypass solves these problems:

1. **API Format Translation**: Claude Code only speaks Anthropic API, but many providers use OpenAI format. APIBypass automatically translates between them — Claude Code can now work with DeepSeek, Qwen, OpenCode Go, and any OpenAI-compatible API.

2. **Parameter Injection**: Set temperature, thinking mode, max tokens, and custom parameters globally without modifying each client.

3. **Model Mapping**: Map the model name your client requests to a different actual model — switch models without changing client config.

4. **Claude Code Launcher**: One-click launch Claude Code in your preferred terminal with all environment variables pre-configured.

### Use Cases

- **Claude Code with OpenAI APIs**: Use Claude Code with DeepSeek, Qwen, or any OpenAI-compatible provider — automatic format translation handles the protocol difference.
- **Closed-source clients**: Some apps don't let you control thinking mode or other parameters. APIBypass injects custom parameters to override defaults.
- **Centralized configuration**: Configure once, use with any client. No need to update each client when changing models or parameters.

![Screenshot](screenshot_configure.png)

<img src="screenshot_launch.png" alt="screenshot_launch" style="zoom: 50%;" />

<img src="screenshot_settings.png" alt="Screenshot" style="zoom:45%;" />

## Features

### API Format Translation (New in v0.5.0)
- Automatic Anthropic ↔ OpenAI format translation
- Request body conversion: system prompts, messages, tools, images, thinking mode
- Response conversion: content blocks, tool calls, usage statistics, stop reasons
- SSE streaming translation: real-time event format conversion for streaming responses
- Smart detection: only translates when client format ≠ upstream provider format

### Claude Code Launcher (New in v0.5.0)
- One-click launch from menu bar
- Terminal selection: Terminal.app, iTerm2, Alacritty, Kitty, Warp, Hyper
- Environment variable injection: ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, ANTHROPIC_MODEL
- Model presets: configure default Opus/Sonnet/Haiku/Subagent models
- Effort level selector: none, low, medium, high, max
- Working directory picker
- Settings persistence between launches

### Provider Management (New in v0.4.0)
- Separate Provider configurations (API type, base URL, API key)
- Model mappings reference providers — no duplicate credentials
- Environment variables per provider for Claude Code integration
- Auto-migration from legacy format

### Core Proxy
- Runs in the macOS menu bar — stays out of your Dock
- Local proxy server on `127.0.0.1:8390` (configurable)
- Auto-start server on app launch
- OpenAI Chat Completions API (`/v1/chat/completions`)
- Anthropic Messages API (`/v1/messages`)
- SSE streaming support — real-time forwarding when `stream: true`

### Model Mapping
- Model name mapping (client request name → actual model)
- Multiple configurations, each independently switchable
- Enable/disable individual configurations at the top of each config page
- Right-click context menu: copy config (including API key), delete config
- Delete confirmation dialog to prevent accidental deletion
- Unsaved changes detection and warning when switching configs

### Parameter Injection
- Temperature, Max Tokens, Top P, Frequency Penalty, Presence Penalty
- Thinking mode override: toggle on/off for Anthropic (`thinking` parameter) and OpenAI-compatible APIs (`enable_thinking` parameter)
- Thinking budget control (Anthropic format)
- Custom JSON fields — inject any parameter with any value type (supports strings, numbers, booleans, objects, arrays)

### Security & Privacy
- API Key stored securely in macOS Keychain (single unified storage)
- Single Keychain authorization for all configurations
- All traffic processed locally — no third-party servers involved
- No telemetry or usage data collected

### UI & UX
- Bilingual interface: Chinese (中文) and English, switchable in Settings
- Three-column layout: Providers sidebar, detail editor, mapping overview
- Resizable panels with draggable dividers
- Save button highlights when changes detected
- Formatted JSON request logging in terminal
- Settings panel with about info, version number, GitHub link (clickable), and License

## System Requirements

- macOS 14.0 or later

## Installation

### Download (Recommended)

Download the latest DMG from the [Releases](https://github.com/panando/APIBypass/releases) page. Mount the DMG and drag APIBypass to your Applications folder. On first launch, allow network connections when prompted.

### Build from Source

Build requirements: Swift 6.0+ / Xcode 16.0+ (or Command Line Tools only)

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass

# Run in debug mode
swift run

# Or build release binary
swift build -c release
.build/arm64-apple-macosx/release/APIBypass
```

On first launch, allow network connections when prompted.

## Usage

### 1. Start the Server

Click the APIBypass icon in the menu bar. The server starts automatically on launch, and the indicator turns green when running on `127.0.0.1:8390` (default port, configurable in Settings). You can also manually start/stop via the menu.

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

The master enable switch at the top of each config page controls whether that mapping is active.

### 4. Parameter Injection

- **Reasoning Mode Override**: Toggle the master switch to control thinking mode:
  - Enable → inject `enable_thinking: true` (OpenAI) or `thinking: {type: "enabled"}` (Anthropic)
  - Disable → inject `enable_thinking: false` or `thinking: {type: "disabled"}`
  - Turn off → don't touch, use API default
- **Standard Parameters**: Fill in Temperature, Max Tokens, Top P, Frequency Penalty, or Presence Penalty to inject.
- **Custom Fields**: Inject arbitrary JSON key-value pairs. Values are auto-detected: `"true"/"false"` → boolean, `"42"` → integer, `"3.14"` → double, `"{\"key\":\"val\"}"` → JSON object.

### 5. Launch Claude Code (New in v0.5.0)

Click "Launch Claude Code" in the menu bar:
1. Select a provider (base URL and API token are auto-configured)
2. Select your preferred terminal
3. Choose a model for `ANTHROPIC_MODEL` (required)
4. Optionally configure Opus/Sonnet/Haiku/Subagent model defaults
5. Set effort level (none, low, medium, high, max)
6. Optionally set a working directory
7. Click "Launch" — Claude Code opens in your terminal with all environment variables set

### 6. Configure Your Client (Manual)

If not using the launcher, point your AI client to `http://127.0.0.1:8390/v1`:

**Example (Cursor):**
```
OpenAI Base URL: http://127.0.0.1:8390/v1
Anthropic Base URL: http://127.0.0.1:8390/v1
```

The API Key field can be anything — the proxy replaces it with your real key.

### 7. Verify (Developers)

When running with `swift run`, watch the terminal for formatted request logs:
- Incoming request body (original)
- Upstream URL and actual model name
- Transformed request body (with injected parameters)
- Format translation status (if applicable)

> This step is for developers. Downloaded DMG users do not see terminal output.

## Settings

Access via menu bar "Settings...". The settings panel provides:

- **Language**: Switch between Chinese (中文) and English — takes effect immediately
- **Server Port**: Configure the local proxy port (default 8390, restart required to apply)
- **About**: Version number, project description, GitHub repository link (clickable), and MIT License info

## Project Structure

```
APIBypass/
├── APIBypassApp.swift          # App entry point + menu bar icon
├── Core/
│   ├── ConfigManager.swift     # Config management (UserDefaults)
│   ├── FormatTranslator.swift  # Anthropic ↔ OpenAI request/response translation
│   ├── HTTPServer.swift        # Hummingbird HTTP server + SSE streaming
│   ├── LocalizationManager.swift  # i18n: Chinese/English strings
│   ├── ProxyEngine.swift       # Request transform engine
│   └── StreamTranslator.swift  # SSE streaming format translation
├── Models/
│   ├── APIProvider.swift       # API provider enum
│   ├── ProviderConfig.swift    # Provider + environment variables
│   └── ModelMapping.swift      # Data models
├── Services/
│   ├── ClaudeCodeLauncher.swift  # Terminal detection + launch
│   ├── KeychainService.swift   # Keychain storage with caching
│   └── NetworkService.swift    # HTTP + streaming network service
├── UI/
│   ├── ConfigWindow.swift      # Config window + new mapping sheet
│   ├── MenuBarView.swift       # Menu bar popup
│   ├── SettingsView.swift      # Settings panel (language + port + about)
│   └── Views/
│       ├── EnvironmentVariablesCard.swift  # Provider env vars config
│       ├── LaunchClaudeCodeView.swift      # Claude Code launcher UI
│       ├── MappingCardView.swift           # Expandable mapping card
│       ├── MappingDetailView.swift         # Config detail editor
│       ├── MappingEditForm.swift           # Shared form component
│       ├── MappingListView.swift           # Config list with context menu
│       ├── NewMappingView.swift            # New mapping sheet
│       ├── NewProviderView.swift           # New provider sheet
│       └── ProviderDetailView.swift        # Provider detail editor
└── Package.swift               # Swift Package manifest
```

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

## Star this project 

Your support means a lot — please star this project if you find it useful.
