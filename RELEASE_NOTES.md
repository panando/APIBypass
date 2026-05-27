# APIBypass v0.4.0

## What's New

### Provider Configuration Management
- Providers section for managing API provider configurations (name, API type, base URL, API key)
- Model mappings reference provider configurations — no more duplicate baseURL/API key entries
- Auto-migration from old format to new provider-based structure with API key preservation

### Hierarchical UI Layout
- Sidebar shows only providers; model mappings are nested inside each provider's detail page
- Expandable mapping cards with inline editing (toggle, parameters, thinking mode, custom fields)
- Right-side mapping overview panel with independent toggle
- Custom sidebar toggle button (fixed position, never moves)
- Draggable dividers for resizable sidebar and mapping panel widths
- Drag-and-drop sorting for providers and mappings

### Quality of Life Improvements
- Copy provider via context menu (duplicates API key + all mappings)
- Provider deletion cascade-deletes all related mappings
- Duplicate incoming model name detection with auto-focus on input field
- Switch toggle on each mapping card for instant enable/disable
- Unsaved changes detection when switching between mapping cards
- Auto-cleanup of orphan mappings on app launch
- Icon color adapts to selection state for visibility

## Changelog

- 46cfc7c: fix: bind List selection to enable item selection
- e0a3dce: docs: add provider config UI improvements design
- a803a22: feat: provider config UI improvements
- 2c10264: feat: UI improvements - save button placement and model name validation
- a5be160: feat: UI improvements for provider detail and sidebar
- 4829004: feat: add unsaved changes detection when switching mapping cards
- b4dc7db: feat: UI fixes - sidebar, focus, mapping panel
- f51698e: fix: sidebar toggle button and bottom toolbar alignment
- e550910: fix: replace NavigationSplitView with custom HStack sidebar
- 8368731: feat: move sidebar toggles to window toolbar, add right panel toggle
- 6fdc545: feat: draggable dividers, toolbar alignment, conditional toggle
- 3a1cad5: fix: mapping panel independent of provider selection, section header style
- d2aed6a: feat: window size, sidebar header, row polish, toolbar text
- 1470a73: fix: simplify toolbar button and provider row design
- 090ad7a: fix: simplify draggable divider, reduce mapping panel default width
- 39098a6: fix: reverse drag direction for mapping panel, update header style
- 6a85ca4: feat: auto-cleanup orphan mappings on app launch
- 515111e: fix: icon color on selection, mapping panel header background
- ccf196b: feat: add i18n keys for new UI elements

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
