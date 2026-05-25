# APIBypass v0.3.1

## What's New

### Custom Server Port
- Server port is now configurable in the Settings panel (default: 8390)
- Port preference persists across app restarts
- Restart the server to apply port changes

### Version Info
- Version number now displayed in the Settings "About" section

### Localization Fix
- Port display text in the menu bar is now properly localized (previously hardcoded in Chinese)

## Changelog

- 230d575: feat: 自定义服务端口、汉化端口文字、关于添加版本号

## Download

- [APIBypass-0.3.1.dmg](https://github.com/panando/APIBypass/releases/tag/v0.3.1)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.3.1
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

## Previous Releases

- [v0.3.0](https://github.com/panando/APIBypass/releases/tag/v0.3.0) - i18n, Settings panel
- [v0.2.2](https://github.com/panando/APIBypass/releases/tag/v0.2.2) - Enable switch toggle at top, UI improvements
- [v0.2.1](https://github.com/panando/APIBypass/releases/tag/v0.2.1) - Right-click context menu, save & switch fix
- [v0.2.0](https://github.com/panando/APIBypass/releases/tag/v0.2.0) - SSE streaming, unified key storage, UI improvements
- [v0.1.4](https://github.com/panando/APIBypass/releases/tag/v0.1.4) - Switch controls for override settings, bug fixes
- [v0.1.3](https://github.com/panando/APIBypass/releases/tag/v0.1.3) - Auto-start server, status indicator, bug fixes
- [v0.1.2](https://github.com/panando/APIBypass/releases/tag/v0.1.2) - Menu bar status indicator
- [v0.1.0](https://github.com/panando/APIBypass/releases/tag/v0.1.0) - Initial release

[Full commit history](https://github.com/panando/APIBypass/commits/main)
