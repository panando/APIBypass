# APIBypass v0.1.3

## What's New

### Auto-start Server
The proxy server now starts automatically when the app launches — no manual step needed. The menu bar icon shows a green dot when running and a gray dot when stopped.

### Status Indicator
A small colored dot overlays the app icon in the menu bar:
- **Green** — server is running
- **Gray** — server is stopped

### Bug Fixes
- Fixed config data loss when switching between mappings in the detail view
- Fixed app crash when closing the config window
- Fixed `enable_thinking` parameter not being injected correctly in OpenAI mode
- Fixed thinking mode section only appearing for Anthropic (now shows for all providers)
- Fixed duplicate `ConfigManager` instances causing config changes to not take effect at runtime

## Changelog

- 69b6545: Auto-start server via labelView.onAppear (correct lifecycle hook)
- 310b192: Draw status dot directly on NSImage using CoreGraphics
- 2b50d65: Fix config duplication (.id mappingId) and window close crash (isReleasedWhenClosed)
- dbc77b1: Fix ConfigManager instance mismatch between UI and server
- 0ce7888: Fix enable_thinking:true not injected when toggle is ON
- 6d05049: Add custom JSON fields support and fix thinking mode logic

## Download

- [APIBypass-0.1.3.dmg](#) (available in Releases)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.1.3
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

[Full commit history](https://github.com/panando/APIBypass/commits/main)
