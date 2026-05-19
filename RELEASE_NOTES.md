# APIBypass v0.1.4

## What's New

### Switch Controls for Override Settings
Added independent switch toggles for both "Reasoning Mode" and "Custom Parameters" sections:
- A master switch to enable/disable the override
- When disabled, settings are preserved but not injected into requests
- When enabled, configured values are applied

### Renamed UI Labels
- "思考模式" → "更改默认推理模式" (Reasoning Mode Override)
- "启用思考模式" → "是否启用思考模式" (Enable Thinking Mode)

### Bug Fixes
- Fixed toggle states being lost after app restart (switch states now persist correctly)
- Fixed boolean and numeric values in custom parameters being incorrectly converted to strings
- `true`/`false` now correctly parsed as booleans
- Numbers now correctly parsed as Int or Double

## Changelog

- c74c872: feat: 改进思考模式和自定义参数的开关控制
- 6d6e84f: fix: 修复自定义参数中布尔值和数字被错误转为字符串的问题

## Download

- [APIBypass-0.1.4.dmg](https://github.com/panando/APIBypass/releases/tag/v0.1.4)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.1.4
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

## Previous Releases

- [v0.1.3](https://github.com/panando/APIBypass/releases/tag/v0.1.3) - Auto-start server, status indicator, bug fixes
- [v0.1.2](https://github.com/panando/APIBypass/releases/tag/v0.1.2) - Menu bar status indicator
- [v0.1.0](https://github.com/panando/APIBypass/releases/tag/v0.1.0) - Initial release

[Full commit history](https://github.com/panando/APIBypass/commits/main)
