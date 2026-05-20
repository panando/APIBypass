# APIBypass v0.2.1

## What's New

### Right-Click Context Menu
Added right-click menu on configuration list items:
- "复制配置" - Duplicate a configuration with all settings and API key
- "删除配置" - Delete a configuration with confirmation dialog

### Save & Switch Fix
Fixed an issue where clicking "保存并切换" in the unsaved changes warning would save but not actually switch to the target configuration.

### Save Button Improvements
- Save button now uses system accent color when changes are detected
- Button appears more subtle when no changes are present
- Better visual feedback for dirty state detection

## Changelog

- 4be2945: feat: 右键菜单和保存切换修复
- 344e8de: feat: 保存按钮变更检测和切换警告

## Download

- [APIBypass-0.2.1.dmg](https://github.com/panando/APIBypass/releases/tag/v0.2.1)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.2.1
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

## Previous Releases

- [v0.2.0](https://github.com/panando/APIBypass/releases/tag/v0.2.0) - SSE streaming, unified key storage, UI improvements
- [v0.1.4](https://github.com/panando/APIBypass/releases/tag/v0.1.4) - Switch controls for override settings, bug fixes
- [v0.1.3](https://github.com/panando/APIBypass/releases/tag/v0.1.3) - Auto-start server, status indicator, bug fixes
- [v0.1.2](https://github.com/panando/APIBypass/releases/tag/v0.1.2) - Menu bar status indicator
- [v0.1.0](https://github.com/panando/APIBypass/releases/tag/v0.1.0) - Initial release

[Full commit history](https://github.com/panando/APIBypass/commits/main)

## What's New

### SSE Streaming Support
Added Server-Sent Events (SSE) streaming support:
- Requests with `stream: true` are now forwarded in real-time
- Compatible with both OpenAI and Anthropic API formats
- Real-time request logging in terminal when running with `swift run`

### Unified API Key Storage
Improved Keychain authorization experience:
- All API keys are now stored in a single Keychain item
- Only one authorization prompt on first access
- Automatic migration from old storage format

### Delete Confirmation
Added confirmation dialog when deleting configurations to prevent accidental deletion.

### UI Improvements
- Enhanced empty state display with helpful guidance
- Moved "Reasoning Mode" section above "Parameter Injection"
- Adjusted custom parameter input ratio to 2:3
- Unified placeholder text for parameter fields
- New configuration defaults to OpenAI format
- Removed duplicate save button

### Terminal Logging
When running with `swift run`, the terminal now displays:
- Formatted JSON request body (original and transformed)
- Upstream URL and actual model name
- Streaming mode indicator

## Changelog

- 2df5dc8: feat: 流式输出支持和多项 UI 优化
- 35296a6: feat: 添加流式输出支持和优化请求日志

## Download

- [APIBypass-0.2.0.dmg](https://github.com/panando/APIBypass/releases/tag/v0.2.0)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.2.0
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

## Previous Releases

- [v0.1.4](https://github.com/panando/APIBypass/releases/tag/v0.1.4) - Switch controls for override settings, bug fixes
- [v0.1.3](https://github.com/panando/APIBypass/releases/tag/v0.1.3) - Auto-start server, status indicator, bug fixes
- [v0.1.2](https://github.com/panando/APIBypass/releases/tag/v0.1.2) - Menu bar status indicator
- [v0.1.0](https://github.com/panando/APIBypass/releases/tag/v0.1.0) - Initial release

[Full commit history](https://github.com/panando/APIBypass/commits/main)

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
