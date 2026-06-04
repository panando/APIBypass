## v0.6.0 — Bypass Mode (Pure Proxy)

### New Feature

- **Bypass Mode (纯代理模式)**: Added a toggle in the menu bar to enable pure proxy mode. When activated, the app transparently passes all requests and responses between client and upstream without any API format conversion, while still preserving model mapping configurations (parameter injection, custom parameters, reasoning toggle, etc.).

### Usage

1. Click the APIBypass icon in the menu bar
2. Click "纯代理模式" (shows ✓ when enabled)
3. All subsequent requests will bypass OpenAI ↔ Anthropic format conversion

### Notes

- Bypass mode is useful when the upstream provider natively supports the same API format as the client, eliminating unnecessary translation overhead.
- High concurrency remains fully supported — bypass mode only skips the format conversion step, all other features (model mapping, parameter injection, API key retrieval, streaming) continue to work normally.
