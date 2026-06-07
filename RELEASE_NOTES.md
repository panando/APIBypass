# APIBypass v0.6.3

## Bug Fixes

- **Fixed layout recursion crash when selecting provider in List**: Added explicit frame constraints to `Toggle.toggleStyle(.switch)` to prevent `NSSwitch intrinsicContentSize` calculation from creating circular layout dependency in nested `ScrollView → VStack → ForEach → MappingCardView → HStack → Toggle` structure on macOS 26.5.1. Previously, clicking between providers in the sidebar caused `LayoutEngineBox.sizeThatFits` to recurse 13+ levels, corrupting heap memory and triggering `EXC_BAD_ACCESS (SIGBUS)`.

## Changelog

- fix: prevent layout recursion crash when selecting provider in List

## Download

- [APIBypass-0.6.3.dmg](https://github.com/panando/APIBypass/releases/tag/v0.6.3)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.6.3
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.6.2

## Bug Fixes

- **Fixed app activation timing**: Moved `activationPolicy` setup from `init()` to `onAppear` to ensure proper app initialization and prevent potential launch issues
- **Fixed Toggle-in-Button crash**: Moved Toggle control outside of Button to prevent SwiftUI rendering crash

## Changelog

- fix: move activationPolicy setup from init() to onAppear
- fix: move Toggle outside Button to prevent crash

## Download

- [APIBypass-0.6.2.dmg](https://github.com/panando/APIBypass/releases/tag/v0.6.2)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.6.2
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.6.1

## What's New

### Built-in Help Window
- **Comprehensive in-app help**: Added a "Help" option in the menu bar that opens a native SwiftUI help window with sidebar navigation covering:
  - Quick Start guide
  - Menu bar options explained
  - Model Mapping concepts and configuration
  - Parameter Injection and Custom Parameters
  - Claude Code Launcher usage
  - Bypass Mode details and when to use it
  - Settings overview
  - Frequently Asked Questions (FAQ)
- **Bilingual Help**: Help content automatically follows the app's current language setting (Chinese / English)

### UI Improvements
- **Improved menu grouping**: Moved "Launch Claude Code" into the same menu group as "Bypass Mode" for better logical organization

### Bug Fixes
- Clarified help documentation: reasoning mode is controlled via `enable_thinking` by default; providers using different fields should use Custom Parameters
- Fixed terminology: "API Token" → "API Key" in the Claude Code Launcher help section

## Changelog

- feat: add built-in Help window with `NavigationSplitView` and sidebar navigation
- feat: add bilingual help content for all major features
- feat: add `HelpView` with 8 sections of documentation
- ui: move "Launch Claude Code" menu item into the Bypass Mode group
- fix: clarify reasoning mode documentation (`enable_thinking` default behavior)
- fix: correct "API Token" to "API Key" in launcher help text

## Download

- [APIBypass-0.6.1.dmg](https://github.com/panando/APIBypass/releases/tag/v0.6.1)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.6.1
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.6.0

## What's New

### Bypass Mode (Pure Proxy)
- **One-click toggle**: Added a "Bypass Mode" option in the menu bar to enable pure proxy mode
- **Transparent passthrough**: When activated, the app passes all requests and responses between client and upstream without any API format conversion, while still preserving model mapping configurations (parameter injection, custom parameters, reasoning toggle, etc.)
- **Use case**: Ideal when the upstream provider natively supports the same API format as the client, eliminating unnecessary translation overhead
- **Full feature compatibility**: High concurrency remains fully supported — bypass mode only skips the format conversion step, all other features (model mapping, parameter injection, API key retrieval, streaming) continue to work normally

## Changelog

- feat: add bypass mode toggle in menu bar
- feat: implement bypass mode in HTTPServer — skips format conversion when enabled
- feat: preserve model mapping and parameter injection in bypass mode

## Download

- [APIBypass-0.6.0.dmg](https://github.com/panando/APIBypass/releases/tag/v0.6.0)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.6.0
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.5.7

## What's New

### Concurrency Performance Optimization
- **Connection limit control**: Implemented `AsyncSemaphore` to limit concurrent connections (default: 100). Returns `503 Service Unavailable` when limit is exceeded, preventing resource exhaustion.
- **Backpressure control**: New `streamWithBackpressure` method with 64KB buffer (64x increase from 1KB) and 8KB checkpoint yielding for smoother concurrent performance.
- **Local model parameter filtering**: Automatically removes 17 local-model-specific parameters (e.g., `num_ctx`, `n_gpu_layers`) that cloud APIs don't accept, preventing `400 Bad Request` errors from providers like Fireworks.

### Streaming Response Fixes
- **JSON error format fix**: Error responses in SSE streams now use proper JSON serialization instead of string concatenation, fixing `AI_JSONParseError` in clients like Cherry Studio.
- **Stream termination fix**: Added `writer.finish(nil)` call after stream completion to properly close HTTP connections, preventing clients from hanging in waiting state.

## Performance Improvements

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Buffer size | 1KB | 64KB | 64x |
| Max concurrent connections | Unlimited | 100 (configurable) | Controlled |
| Thread yielding | None | Every 8KB | Smoother |
| Byte-by-byte processing | Yes | No | Batch processing |

## Changelog

- feat: add `AsyncSemaphore` for concurrent connection limiting
- feat: implement `streamWithBackpressure` with 64KB buffer and backpressure control
- feat: filter 17 local model parameters (`num_ctx`, `n_ctx`, `n_gpu_layers`, etc.)
- fix: JSON serialization for SSE error responses (fixes `AI_JSONParseError`)
- fix: call `writer.finish(nil)` to close streaming connections properly
- perf: 64KB buffer size (was 1KB)
- perf: `Task.yield()` every 8KB for cooperative multitasking

## Download

- [APIBypass-0.5.7.dmg](https://github.com/panando/APIBypass/releases/tag/v0.5.7)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.5.7
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.5.6

## What's New

### SSE Compatibility Fix
- **Fixed SSE parsing for non-standard providers**: Resolved an issue where some API providers (e.g., MiMo) return SSE events without blank line separators, causing complete response failure. The decoder now correctly handles both standard and non-standard SSE formats.

### Extended Thinking Support
- **Anthropic → OpenAI thinking conversion**: When converting Anthropic streaming responses to OpenAI format, `thinking_delta` blocks are now mapped to OpenAI's native `reasoning_content` field, ensuring seamless display in OpenAI-compatible clients.
- **Redacted thinking handling**: `redacted_thinking` blocks are converted to a placeholder message in `reasoning_content`.

### Claude Code Launcher Improvements
- **Simplified default templates**: Reduced from 3 preset templates to 1 empty "Default" template for cleaner initial state.
- **Unified UI styling**: Terminal selection section now matches the environment variables section with consistent border styling.

## Changelog

- fix: SSE decoder compatibility with non-standard SSE format (no blank line separators)
- feat: convert Anthropic `thinking_delta` to OpenAI `reasoning_content` in streaming translation
- feat: handle `redacted_thinking` blocks in Anthropic → OpenAI conversion
- feat: add `signature_delta` handling (ignored for single-turn, needed for multi-turn continuity)
- refactor: simplify default templates to single empty "Default" template
- style: unify terminal selection section border with environment variables section
- chore: add debug logging for SSE stream processing

## Download

- [APIBypass-0.5.6.dmg](https://github.com/panando/APIBypass/releases/tag/v0.5.6)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.5.6
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.5.3

## What's New

### Cross-Provider Model Selection in Claude Code Launcher
- **Per-model provider picker**: each model environment variable (ANTHROPIC_MODEL, OPUS, SONNET, HAIKU, SUBAGENT) now has an independent two-tier picker — first select the provider, then choose a mapping from that provider
- **Removed top-level provider selector**: the previous single provider picker at the top of the launcher is no longer needed, since each model carries its own provider context
- All five models can now route to different upstream providers simultaneously

## Changelog

- feat: two-tier model selection (provider → mapping) per model in Claude Code launcher
- feat: cross-provider model support — each env var model can target a different provider
- feat: remove redundant top-level provider picker from launcher UI
- docs: update screenshot for new launcher layout

## Download

- [APIBypass-0.5.3.dmg](https://github.com/panando/APIBypass/releases/tag/v0.5.3)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.5.3
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.5.2

## What's New

### Claude Code Compatibility
- **Strip `cch` billing headers**: automatically removes `cch` request identifiers from headers to prevent billing conflicts when using Claude Code with non-Anthropic providers
- **CLAUDE_CODE_ATTRIBUTION_HEADER toggle**: new control in the Claude Code launcher to enable or disable the `CLAUDE_CODE_ATTRIBUTION_HEADER` environment variable

### OpenAI Responses API Support
- Added proxy support for the OpenAI Responses API endpoint (`/v1/responses`)
- Responses API format is handled alongside Chat Completions for seamless integration

### Bug Fixes & Improvements
- **Fixed URL building**: proxy now correctly constructs upstream URLs for providers with non-standard paths (e.g., `/v3`)
- **Fixed streaming error responses**: upstream errors during SSE streaming are now returned in proper SSE format with correct `data:` prefix and newline termination
- **Build warnings cleaned up**: removed unused variable initialization

## Changelog

- feat: add OpenAI Responses API (`/v1/responses`) proxy support
- feat: add RectifierModels for Claude Code billing header handling
- feat: strip `cch` billing headers in HTTPServer
- feat: add CLAUDE_CODE_ATTRIBUTION_HEADER toggle in Claude Code launcher
- fix: upstream URL building for providers with non-`/v1` paths
- fix: SSE streaming error response format
- chore: remove unused `baseURLString` variable
- docs: update README and README_CN with v0.5.2 features

## Download

- [APIBypass-0.5.2.dmg](https://github.com/panando/APIBypass/releases/tag/v0.5.2)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.5.2
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.5.1

## What's New

### Bug Fixes
- **Fixed build warnings**: removed unused variable initialization

## Changelog

- chore: fix build warnings (unused `baseURLString`)
- chore: update screenshots

## Download

- [APIBypass-0.5.1.dmg](https://github.com/panando/APIBypass/releases/tag/v0.5.1)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.5.1
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.5.0

## What's New

### API Format Translation
- **Automatic Anthropic ↔ OpenAI format translation**: Claude Code can now work with any OpenAI-compatible API (DeepSeek, Qwen, OpenCode Go, etc.)
- Request translation: system prompts, messages, tools, tool_choice, thinking mode, images, stop sequences
- Response translation: content blocks, tool calls, usage statistics, stop reasons
- **SSE streaming translation**: Real-time event format conversion for streaming responses
- Smart detection: only translates when client format ≠ upstream provider format
- Bidirectional: Anthropic→OpenAI and OpenAI→Anthropic

### Claude Code Launcher
- **One-click launch from menu bar**: Pre-configured environment variables, no manual setup
- Terminal selection: Terminal.app, iTerm2, Alacritty, Kitty, Warp, Hyper (auto-detected)
- Environment variable injection:
  - `ANTHROPIC_BASE_URL` (from provider)
  - `ANTHROPIC_AUTH_TOKEN` (from Keychain)
  - `ANTHROPIC_MODEL` (select from mappings)
  - `ANTHROPIC_DEFAULT_OPUS_MODEL`, `SONNET_MODEL`, `HAIKU_MODEL`
  - `CLAUDE_CODE_SUBAGENT_MODEL`
  - `CLAUDE_CODE_EFFORT_LEVEL` (dropdown: none, low, medium, high, max)
- Working directory picker
- Settings persistence between launches

### Provider Environment Variables
- Environment variables configuration per provider
- Variable types: Manual input, Model mapping, Keychain token, Base URL
- Auto-generate default environment variables for new providers
- Reset to defaults button

### Internationalization
- Complete bilingual support (Chinese/English) for all UI elements
- Parameter names localized (Temperature, Max Tokens, Top P, etc.)
- API provider type labels localized
- Launcher error messages localized

## Changelog

- feat: add FormatTranslator for Anthropic↔OpenAI request/response conversion
- feat: add StreamTranslator for SSE streaming format translation
- feat: integrate format translation in HTTPServer
- feat: add Claude Code launcher with terminal detection
- feat: add LaunchClaudeCodeView UI
- feat: add EnvironmentVariablesCard for provider config
- feat: add environment variables to ProviderConfig model
- feat: add migration for provider environment variables
- feat: add Launch Claude Code menu item
- feat: add CLAUDE_CODE_EFFORT_LEVEL dropdown selector
- feat: complete i18n for all UI components

## Download

- [APIBypass-0.5.0.dmg](https://github.com/panando/APIBypass/releases/tag/v0.5.0)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.5.0
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

## Previous Releases

- [v0.6.3](https://github.com/panando/APIBypass/releases/tag/v0.6.3) - Layout recursion crash fix
- [v0.6.2](https://github.com/panando/APIBypass/releases/tag/v0.6.2) - Activation fix, Toggle-in-Button crash fix
- [v0.6.1](https://github.com/panando/APIBypass/releases/tag/v0.6.1) - Built-in Help Window, UI improvements
- [v0.5.2](https://github.com/panando/APIBypass/releases/tag/v0.5.2) - OpenAI Responses API, Claude Code compatibility fixes, URL building improvements
- [v0.5.1](https://github.com/panando/APIBypass/releases/tag/v0.5.1) - Build warnings cleanup
- [v0.5.0](https://github.com/panando/APIBypass/releases/tag/v0.5.0) - API format translation, Claude Code launcher, i18n
- [v0.4.0](https://github.com/panando/APIBypass/releases/tag/v0.4.0) - Provider management, hierarchical UI
- [v0.3.2](https://github.com/panando/APIBypass/releases/tag/v0.3.2) - Proxy header fix, SSE streaming improvement
- [v0.3.1](https://github.com/panando/APIBypass/releases/tag/v0.3.1) - Custom server port, version info, localization fix
- [v0.3.0](https://github.com/panando/APIBypass/releases/tag/v0.3.0) - i18n, Settings panel
- [v0.2.2](https://github.com/panando/APIBypass/releases/tag/v0.2.2) - Enable switch toggle at top, UI improvements
- [v0.2.1](https://github.com/panando/APIBypass/releases/tag/v0.2.1) - Right-click context menu, save & switch fix
- [v0.2.0](https://github.com/panando/APIBypass/releases/tag/v0.2.0) - SSE streaming, unified key storage, UI improvements
- [v0.1.4](https://github.com/panando/APIBypass/releases/tag/v0.1.4) - Switch controls for override settings, bug fixes
- [v0.1.3](https://github.com/panando/APIBypass/releases/tag/v0.1.3) - Auto-start server, status indicator, bug fixes
- [v0.1.2](https://github.com/panando/APIBypass/releases/tag/v0.1.2) - Menu bar status indicator
- [v0.1.0](https://github.com/panando/APIBypass/releases/tag/v0.1.0) - Initial release

[Full commit history](https://github.com/panando/APIBypass/commits/main)
