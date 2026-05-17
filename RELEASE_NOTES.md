# APIBypass v1.0.0

A lightweight macOS menu bar app that acts as a local LLM API proxy. Intercept and customize API parameters before they reach the upstream provider.

---

## Getting Started

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
swift build -c release
swift run
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

## Features

### Core Proxy
- Local HTTP proxy server on `127.0.0.1:8390`
- OpenAI Chat Completions API (`/v1/chat/completions`)
- Anthropic Messages API (`/v1/messages`)
- Streaming response passthrough
- Smart URL construction (handles `/v1` suffix in base URL)

### Model Name Mapping
- Map incoming model names to different actual models
- Multiple mappings with independent configurations
- Enable/disable individual mappings without deleting them

### Parameter Injection
- **Temperature** (0.0 – 2.0)
- **Max Tokens** (integer)
- **Top P** (0.0 – 1.0)
- **Frequency Penalty** (-2.0 – 2.0)
- **Presence Penalty** (-2.0 – 2.0)

### Thinking Mode Control
- Master toggle to opt-in/out of thinking mode override
- **Anthropic**: sends `thinking: {"type": "enabled"/"disabled"}` with configurable budget tokens
- **OpenAI-compatible**: sends `enable_thinking: true/false` for DeepSeek/Qwen3/GLM and other third-party APIs
- Disabled state fully omits the parameter, leaving API defaults untouched

### Custom Fields
- Inject arbitrary JSON key-value pairs into requests
- Values support JSON types: strings, numbers, booleans, objects, arrays
- Override any API parameter not covered by the built-in fields

### Security
- API Keys stored in macOS Keychain (`kSecAttrAccessibleWhenUnlocked`)
- Duplicate key handling with proper update semantics
- No hardcoded credentials in source code

### Debugging
- Console request logging with `[APIBypass]` prefix
- Logs original request body, transformed body, upstream URL, and actual model

## UI
- macOS menu bar app with green/red status indicator
- Navigation split-view config window (list + detail)
- Dedicated new mapping sheet with form validation
- All views use `ScrollView + VStack` layout for reliable text input on macOS

## Fixes in This Release

- Config window text input not working on macOS menu bar apps
- Config window not appearing after activation policy changes
- Server blocking main thread (now runs in background `Task`)
- 404 errors from double `/v1/v1/` URL construction
- Config changes not taking effect due to separate `ConfigManager` instances
- Thinking mode section incorrectly shown for non-Anthropic providers
- `enable_thinking` not injected when thinking toggle is ON (OpenAI mode)

## Known Limitations

- No HTTPS support for the local proxy (HTTP only, localhost is safe)
- No authentication on the proxy endpoint (designed for local use only)
- Cannot combine multiple mappings into a single request transformation
- All configuration done via GUI; no CLI or config file import/export

---

**Full Changelog**: https://github.com/panando/APIBypass/commits/main
