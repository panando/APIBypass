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
