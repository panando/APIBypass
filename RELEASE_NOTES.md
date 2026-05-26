# APIBypass v0.3.2

## What's New

### Proxy Header Fix
- Fixed a bug where `content-encoding: gzip` was forwarded to clients after URLSession had already decompressed the response body, causing connection errors with some API providers (e.g., DashScope)
- Now properly filters hop-by-hop headers (`transfer-encoding`, `connection`, `content-length`, `content-encoding`, `keep-alive`) per HTTP specification

### SSE Streaming Improvement
- SSE events are now forwarded line-by-line in real time instead of in 8KB chunks, enabling character-by-character streaming output as expected

### Debug Logging
- Added upstream response status and error body logging for easier troubleshooting

## Changelog

- 80b01fc: fix: 过滤代理转发中的 hop-by-hop 和 content-encoding header
- (this commit): fix: SSE 流式输出改为逐行实时转发，修复批量输出问题

## Download

- [APIBypass-0.3.2.dmg](https://github.com/panando/APIBypass/releases/tag/v0.3.2)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.3.2
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

## Previous Releases

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
