# APIBypass v0.4.0

## What's New

### Provider Configuration Management
- New "Providers" section in the sidebar for managing API provider configurations
- Each provider configuration includes: name, API type (OpenAI/Anthropic), base URL, and API key
- Model mappings now reference provider configurations instead of storing duplicate baseURL/API key
- Easier management when using the same provider across multiple model mappings

### Improved UI Organization
- Sidebar now shows "Providers" and "Model Mappings" as separate sections
- Add new providers directly from the mapping creation dialog
- Delete provider warning shows how many mappings will be affected
- Invalid mappings (missing provider) display a warning indicator

### Automatic Data Migration
- Existing configurations automatically migrated to the new provider-based structure
- API keys preserved during migration
- Old mappings grouped by (provider type, base URL) to create provider configurations

## Changelog

- f69588f: feat: add ProviderConfig data model
- 16f484d: feat: update ModelMapping to use providerConfigId
- 391f08a: feat: extend ConfigManager with providers management and data migration
- 5552444: feat: update HTTPServer to use provider from ConfigManager
- 7e94008: feat: add ProviderDetailView and NewProviderView
- 89de8c1: feat: restructure UI with provider/mapping split layout

## Download

- [APIBypass-0.4.0.dmg](https://github.com/panando/APIBypass/releases/tag/v0.4.0)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.4.0
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

## Previous Releases

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
