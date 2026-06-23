# APIBypass v0.8.3

## What's New

### Auto-inject `max_tokens` for Anthropic API

Anthropic API requires the `max_tokens` field, but OpenAI-format clients (like Codex Adapter) don't always include it. This release auto-injects a default value when converting OpenAI requests to Anthropic format.

- When `FormatTranslator.openAIToAnthropicRequest()` converts a request without `max_tokens`, it now injects a default value of `8192`.
- If the client already provides `max_tokens`, the value is preserved.
- Added unit tests covering auto-injection, preservation of existing values, and non-injection for OpenAI format.

### Codex Adapter Pipe Deadlock Fix

Fixed a potential deadlock in `CodexConfigService` when reading Codex template output:

- Pipe data is now read **before** `waitUntilExit()` to avoid blocking when output exceeds the pipe buffer (~64KB).
- Previously, large outputs could cause the process to hang indefinitely.

---

# APIBypass v0.8.0

## What's New

### Distribution Package Fixes

This release fixes the Apple Silicon macOS packaging flow for users downloading APIBypass from GitHub Releases.

- The final `.app` bundle is now ad-hoc signed after assembly, so `Info.plist` and bundled resources are sealed correctly.
- The build script removes local Xcode toolchain rpaths from the executable before signing.
- `libswiftCompatibilitySpan.dylib` is embedded into `Contents/Frameworks` when required, avoiding launch failures on machines without the same Xcode toolchain installed.
- The DMG build now verifies both the local `.app` and the app mounted from the generated DMG.

### Release Verification

A new release verification script checks the generated app bundle before shipping:

- strict codesign verification
- rejection of `/Applications/Xcode.app/...` load paths
- Gatekeeper distribution precheck with only the expected no-certificate failures accepted

### Unsigned Build Documentation

The README now explains that current releases are ad-hoc signed and not Apple-notarized, and includes beginner-friendly steps for opening the app when macOS reports that it is damaged.

> Note: APIBypass still does not have a Developer ID certificate. Gatekeeper may still require manual approval or quarantine removal for downloaded releases.

---

# APIBypass v0.7.9

## What's New

### Help Page Overhaul

The in-app help window was rewritten end to end — new table of contents, new sections, and a proper typographic hierarchy.

- **Reorganized TOC**: Quick Start, Menu Bar, Model Mapping, Parameter Injection, Thinking Protocol, Bypass Mode, Launcher, Codex Adaptor, Custom Models, Settings, FAQ — ordered to follow the natural setup flow.
- **New sections**: Thinking Protocol (explains the three protocols and the auto-inference), Custom Models (alias / source / context window), plus expanded Codex Adaptor and Launcher coverage (configurable port, reasoning override, auto-detect, cache optimization, rectifier, keychain, templates).
- **Typographic hierarchy**: section titles bold/black/large; body, bullets, and notes de-emphasized in gray. Feature names inside list items are bolded (e.g. **Custom Models** — ...) so the term is distinguishable from its description.
- **Bordered group cards**: multi-subtopic sections are wrapped in individual cards with separator borders, mirroring the FAQ styling.
- **Stable sidebar toggle**: the sidebar visibility button is now pinned to the toolbar's leading edge via `ToolbarItem(.navigation)` — it no longer jumps left/right when clicked.
- **Wider default window** (960×640) and increased in-paragraph line spacing for readability.
- Full Chinese/English bilingual content, with jargon like "落盘" replaced by plain wording ("写入文件").

### Settings Window Redesign

- **Language on a single row**: the segmented picker sits inline with the title instead of on a second line.
- **Auto-sizing window**: the settings window is now resizable and miniaturizable, sizing to its content.
- **Trace log group tightened**: the toggle is placed directly next to its title, and when enabled the log file path appears below the description in monospaced, selectable text.
- Renamed "服务端口" → "API中转服务端口" and shortened the trace-log description.
- Consistent `cardStyle()` across all three groups with tighter spacing.

### About Panel

- The GitHub link (`https://github.com/panando/APIBypass`) now actually renders. `Credits.rtf` is bundled via SPM resources and loaded through `Bundle.module` into the standard About panel.
- Panel widened to 480pt and centered; copyright set to "MIT License" via `NSHumanReadableCopyright` in Info.plist.
- An **About** entry was added to the menu-bar menu (previously only accessible via the app menu).

### Trace Log Directory Renamed

The trace log folder moved from `~/Library/Logs/com.apibypass.app/trace/` to `~/Library/Logs/APIBypass/trace/`. The old reverse-DNS name made Finder render it as an app-bundle icon rather than a normal folder. The logger also no longer opens a file handle when trace logging is disabled.

---

# APIBypass v0.7.8

## What's New

### Redesigned Thinking Control Field

The "Reasoning Mode Override" section was rebuilt around a single **Thinking Field** picker with three protocols, replacing the previous four-case design:

- **`enable_thinking`** — Qwen3 series (DashScope). A switch toggles the boolean field on/off.
- **`thinking.type` (Anthropic native)** — Claude / GLM / Kimi / DeepSeek / Doubao. A switch toggles `thinking.type` between `enabled` and `disabled`.
- **`none`** — Models that control thinking internally (OpenAI o-series, gpt-5, DeepSeek-R1). No switch field is emitted; an optional **Reasoning Effort** free-text input lets you inject `reasoning_effort` (e.g. `low` / `medium` / `high` / `xhigh`).

The protocol is **auto-inferred** from the provider baseURL and model name, and can be manually overridden per mapping. Backward compatible: configs saved with the old `reasoning_effort` protocol value decode to the new `none` case.

### Collapsible Mapping Sections

In the expanded mapping card, the **Reasoning Mode Override** and **Custom Parameters** sections now collapse to a single title row when their switch is off, instead of greying out their contents. This keeps the editor compact and the inactive state unambiguous.

### Grouped Section Borders

The four editor sections — Basic Info, Reasoning Mode Override, Parameter Injection, Custom Parameters — are now wrapped in individual bordered cards inside the mapping card, making the grouping clearer at a glance. The provider info line under Basic Info is left-aligned.

### Other

- Removed the divider between the thinking-protocol picker and the enable-thinking toggle.
- `MappingCardView` no longer carries a `thinkingBudget` state (budget fields were dropped from the model).

---

# APIBypass v0.7.7

## What's New

### Fix: Subagent Empty Returns and Thinking Context Loss

Fixed two bugs in the Anthropic→OpenAI request translation path that caused Claude Code subagents (Task tool) to return empty results when routed through APIBypass to GLM / Kimi / DeepSeek upstreams:

- **`tool_result` array content dropped**: Claude Code sends `tool_result.content` as an array of content blocks, but the translator only handled the string form via `as? String`, falling back to an empty string. Parent agents then received empty tool results. Now both string and array forms are parsed correctly.
- **`thinking` blocks in assistant history dropped**: Assistant messages carrying `thinking` blocks fell through the `default` branch and were silently discarded. GLM / Kimi / DeepSeek require `reasoning_content` to be preserved across turns for multi-turn tool calling — losing it caused 400 errors or degraded reasoning continuity. `thinking` blocks are now carried through as `reasoning_content`.

### TraceLogger

Added an internal trace logger that dumps upstream/downstream SSE events keyed by request ID, wiped and rebuilt on each app launch. Logs are written to `~/Library/Logs/com.apibypass.app/trace/`.

> Note: only affects the Anthropic-client → OpenAI-upstream path. OpenAI→OpenAI passthrough, OpenAI→Anthropic, and Anthropic→Anthropic are unchanged.

---

# APIBypass v0.7.6

## What's New

### Streaming Token Usage for OpenAI-Compatible Providers

Added a provider-level switch: **Request streaming token usage** (请求流式 token 用量). When enabled, APIBypass adds `stream_options.include_usage=true` to OpenAI-compatible streaming requests for that provider, allowing clients such as Claude Code to display context percentage and token usage when the upstream provider requires explicit usage reporting.

- Enabled by default for existing and new providers
- Only applies to OpenAI-compatible streaming upstream requests
- Preserves client-provided `stream_options` without overriding them
- Can be disabled per provider if an upstream API does not support `stream_options` / `include_usage`
- Includes an info popover explaining when to enable or disable the option

### UI Improvements

- Improved the provider settings UI with a compact stream-usage switch and clearer help text
- Renamed the global model-name option to **Model Name Fix** (模型名校正)
- Improved the sidebar model-name toggle layout for better visual consistency
- Added drag handles and drag-and-drop reordering for provider model mappings
- Added drag-and-drop reordering for Codex Adaptor custom models
- Refined Codex Adaptor custom model column sizing and header hierarchy

## Download

- [APIBypass-0.7.6.dmg](https://github.com/panando/APIBypass/releases/tag/v0.7.6)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.7.6
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.7.5

## What's New

### Return Requested Model Name

Added a global toggle in the config window sidebar: **"Return Requested Model"** (返回请求模型名). When enabled, the `model` field in API responses matches the client's requested model name instead of the upstream actual model name.

This solves a common problem: some AI clients strictly validate that the response's `model` field matches the request. For example, if you request `glm-5.1-ark` (mapped to upstream `glm-5.1`), the response would normally return `glm-5.1` — causing validation failures. Enabling this toggle ensures the response returns `glm-5.1-ark`, consistent with what the client sent.

- Works for both streaming and non-streaming responses
- Works across all API format combinations (OpenAI, Anthropic, with or without format translation)
- Toggle is located at the bottom of the config window sidebar, separated from the provider list
- Click the info icon next to the toggle for a detailed explanation with example

### README: Credential Protection

Added a new pain point to the README: many AI clients require you to enter provider API Keys directly, exposing your real credentials and base URL. APIBypass solves this — your real API Key stays in macOS Keychain and is injected at request time. Clients only see the local proxy address.

## Download

- [APIBypass-0.7.5.dmg](https://github.com/panando/APIBypass/releases/tag/v0.7.5)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.7.5
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.7.4

## What's New

### Codex Adaptor: Custom Models UI Overhaul

- **Unified row style**: Adding a model now inserts a standard row (with trash button) instead of a separate inline form with X/checkmark buttons. Deleting via trash button saves immediately — no double confirmation needed
- **Context Window**: New model entries no longer pre-fill 128000. The field is empty with placeholder text, preventing accidental saves of default values

### Codex Adaptor: Reasoning Configuration Improvements

- **Auto-Detect button repositioned**: Moved from the override toggle row to inside the override panel, appearing next to the toggle when enabled. It now only fills parameters without automatically enabling the override switch
- **Info popover**: Added an info button (ℹ) next to the "auto-detection is used when no override is set" hint. Clicking it shows how inference works, which providers are supported, and what happens when no match is found

### Settings Panel

- **Section titles**: Changed from `.subheadline` secondary style to `.headline` for clearer visual hierarchy
- **Language picker**: Left-aligned instead of centered; removed the "takes effect immediately" hint text

### Menu Bar

- **Status indicator position**: Moved the two status dots from bottom-left/bottom-right to top-left/top-right of the menu bar icon

### Localization

- **Menu bar**: "启动 CodexAdaptor 服务" → "启动 Codex 适配服务" (Chinese)

# APIBypass v0.7.3

## What's New

### Menu Bar Dual Status Indicator

The menu bar icon now shows two status dots — one for each service:

- **Bottom-left**: Codex Adaptor (green = running, gray = stopped)
- **Bottom-right**: APIBypass server (green = running, gray = stopped)

Same dot style and color logic as before (5px oval, systemGreen / systemGray). You can now see the status of both services at a glance.

### Menu Bar Start/Stop for Codex Adaptor

- **New menu item**: "Start/Stop CodexAdaptor" — control the Codex Adaptor proxy directly from the menu bar
- **Renamed existing item**: "Start/Stop APIBypass" (was "Start/Stop Server") for clarity
- **Removed status text**: The running/stopped text and port number have been removed from the menu. Status is now shown exclusively via the icon dots — cleaner and less visual noise

### Codex Adaptor Custom Models: Save/Cancel Buttons

The Custom Models section now uses a draft-working-copy pattern with explicit **Save** and **Cancel** buttons:

- Edits to model aliases, mappings, and context windows are held in a draft until you commit them
- **Save** persists changes and syncs to UserDefaults + `~/.codex/providers.json`
- **Cancel** reverts all changes to the last saved state, including any in-progress add form
- Add and delete operations only modify the draft — no more auto-save
- Buttons only appear when there are unsaved changes, keeping the UI clean

### Other Changes

- README: All "Codex CLI" references replaced with "Codex"
- Updated icon assets

## Download

- [APIBypass-0.7.3.dmg](https://github.com/panando/APIBypass/releases/tag/v0.7.3)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.7.3
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.7.2

## What's New

### Config Auto-Recovery from providers.json

When Codex Adaptor configuration is missing from UserDefaults (e.g., after clearing app data), the app now automatically recovers settings from `~/.codex/providers.json` — the derived output generated during the last service startup. This prevents data loss for custom models, wire API, and reasoning configuration.

- **Wire API**: Restored from `upstreamWireAPI`
- **Reasoning config**: Full recovery including all thinking/effort overrides
- **Custom models**: Model slugs matched against APIBypass mappings by `incomingModel`, restoring aliases and context windows
- Recovered config is persisted back to UserDefaults immediately

### Bug Fixes

- **Menu bar language switching**: Fixed menu bar not re-rendering when switching between Chinese/English — changed `private let` to `@ObservedObject private var` for `LocalizationManager`

## Download

- [APIBypass-0.7.2.dmg](https://github.com/panando/APIBypass/releases/tag/v0.7.2)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.7.2
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.7.0

## What's New

### Codex Adaptor — Built-in Responses API Proxy for Codex CLI

The [codex-adapter](https://github.com/panando/codex-adapter) project is now fully integrated into APIBypass as a built-in feature. Launch from the menu bar "Codex适配器" (Codex Adaptor) to run a local proxy that translates Codex CLI's Responses API calls into Chat Completions format, then forwards them through APIBypass for model mapping and parameter injection.

**Architecture**: Codex CLI → Codex Adaptor proxy (:15721) → APIBypass server (:8390) → upstream API provider

- **Communication Protocol**: Choose between Chat Completions or Responses API wire format, with contextual guidance
- **Reasoning Configuration**: Auto-detect or manually configure thinking/effort parameters per provider (DeepSeek, OpenRouter, SiliconFlow, MiniMax, Qwen, etc.)
- **Custom Models**: Define model display names that map to APIBypass model mappings via dropdown selector, with configurable context windows
- **CDP Enhancements** (switch-toggle style): Force entry unlock, plugin marketplace unlock, and force plugin install for the Codex Electron app
- **Real-time Logs**: Built-in log viewer with filtering, auto-scroll, copy all, export, and clear

### Thread Safety Architecture

- **CodexLogStore**: Removed `ObservableObject`/`@Published` to eliminate Combine → SwiftUI → AutoLayout crashes from background threads. UI now polls via `Timer` for thread-safe log updates, following the same data/UI separation pattern established in `ConfigDataStore`/`ConfigManager`
- **CodexProxyServer**: Fixed stop button — server now properly shuts down via `Task.cancel()` propagating through Hummingbird's `ServiceGroup` graceful shutdown, instead of just dropping the reference
- **ModelCatalog**: Added `Sendable` conformance to `ModelCatalog` and `ModelCatalogEntry` to resolve Swift 6 concurrency warnings
- **ConfigDataStore**: Added `getFirstEnabledMapping()` for fast lookup

### UI Refinements

- Sidebar navigation redesign matching the original codex-adapter project layout
- Card-style sections with consistent styling (rounded corners, subtle borders)
- Custom Models section with proper column headers, inline add/delete, and confirmation dialogs
- Communication Protocol description explaining when to use Chat Completions vs Responses API
- Switch toggles with right-aligned layout and smaller control size in Codex Enhancements
- Removed unused debug port option from Codex Enhancements
- Empty placeholder text for context window field

### Bug Fixes

- **Double /v1 URL**: Fixed upstream path construction — removed `/v1` prefix from `upstreamPath()` since base URL already includes it
- **Request loop**: Fixed proxy forwarding back to itself — pointed upstream URL to APIBypass server (127.0.0.1:8390) instead of proxy port
- **Model name resolution**: Codex Adaptor now resolves Codex model aliases → APIBypass model names through model catalog in proxy handler, enabling the full Codex CLI → proxy → APIBypass → upstream flow
- **Stop button**: Proper server shutdown with Task cancellation

### Localization

- Menu bar "Codex Adaptor" displays as "Codex适配器" in Chinese UI
- 25+ new localization keys for Codex Adaptor UI (en/zh), with descriptions matching the original project
- Communication protocol guidance localized

## Download

- [APIBypass-0.7.0.dmg](https://github.com/panando/APIBypass/releases/tag/v0.7.0)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.7.0
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.6.6

## What's New

### Removed Responses API Support
- **Removed OpenAI Responses API (`/v1/responses`) endpoint**: The project now focuses exclusively on Chat Completions API and Anthropic Messages API. Responses API format conversion will be reintroduced later via a dedicated CodexAdaptor module.

### Simplified Architecture
- **Removed `APIFormat.responses` enum case**: The core format routing now only supports two formats: OpenAI Chat Completions and Anthropic Messages.
- **Removed `APIProvider.openaiResponses` provider type**: Provider configuration UI no longer shows the Responses API option.
- **Cleaned up ~500 lines of Responses-specific translation code**: Removed 8 format conversion methods and 5 usage mapping helpers from `FormatTranslator`.

## Changelog

- refactor: remove `/v1/responses` endpoint from HTTPServer
- refactor: remove `APIFormat.responses` from ProxyEngine
- refactor: remove `APIProvider.openaiResponses` from APIProvider model
- refactor: remove Responses request/response translation methods from FormatTranslator
- refactor: remove Responses usage mapping helpers from FormatTranslator
- refactor: remove `.openaiResponses` case from NetworkService auth switch
- refactor: remove Responses option from provider UI pickers
- refactor: remove `provider_type_openai_responses` localization key

## Download

- [APIBypass-0.6.6.dmg](https://github.com/panando/APIBypass/releases/tag/v0.6.6)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.6.6
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.6.5

## What's New

### Warp/Warpl Terminal Support
- **Added Warp and Warpl terminal detection**: The Claude Code Launcher now detects both `Warp.app` and `Warpl.app` installations. App name and bundle ID are read dynamically from the app's `Info.plist`, ensuring compatibility across different versions.
- **No accessibility permission required**: Warp/Warpl launch uses a temporary shell script written to the working directory + `open -a` command. The script auto-deletes itself on execution. No System Events keystroke access needed.

### UI Fixes
- **Fixed terminal/working directory selection not persisting**: Terminal and working directory selections were not saved when changed. Added `onChange` handlers for both fields and `onDisappear` auto-save on window close.
- **Added accessibility permission error UI**: When other terminals (e.g., Terminal.app new tab) require accessibility permission but it's not granted, the error message now includes a button to open System Settings > Accessibility.

## Changelog

- feat: add dynamic detection for Warp/Warpl terminal
- feat: add Warp/Warpl launch via temporary script + `open -a` (no accessibility permission needed)
- fix: persist terminal selection on change
- fix: persist working directory selection on change
- fix: auto-save settings on launcher window close
- feat: add accessibility permission error with System Settings button
- feat: add `LauncherError.accessibilityDenied` error type

## Download

- [APIBypass-0.6.5.dmg](https://github.com/panando/APIBypass/releases/tag/v0.6.5)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.6.5
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.6.4

## Bug Fixes

- **Fixed thread safety crashes on macOS 26.5.1**: Implemented actor-based architecture for `KeychainService` and `ConfigDataStore` to eliminate data races between SwiftUI rendering (main thread) and HTTP request handling (background threads). Previous architecture had unsynchronized dictionary access causing memory corruption and `EXC_BAD_ACCESS` crashes.

- **Fixed JSON serialization crash in FormatTranslator**: Removed invalid `NSJSONSerialization.dataWithJSONObject:` call with `String` argument. `NSJSONSerialization` only accepts `NSArray` or `NSDictionary` as top-level objects. The `system` field in Anthropic API now correctly receives a plain string.

- **Fixed save button incorrectly enabled on provider selection**: Fixed async timing issue where `loadOriginalData()` was called before keychain finished loading, causing `hasChanges` to always be `true` on initial provider selection.

- **Fixed MainActor isolation for ConfigManager**: Ensured thread-safe access to `ConfigManager` in HTTP handlers by properly isolating UI-bound properties on `@MainActor` while background HTTP handlers access the data store directly.

## Changelog

- fix: implement actor-based ConfigDataStore for thread safety
- fix: make KeychainService thread-safe using Swift actor
- fix: prevent Toggle layout recursion crash on macOS 26.5.1
- fix: remove @ObservedObject wrapper for LocalizationManager singleton
- fix: ensure thread-safe access to ConfigManager in HTTP handlers
- fix: ensure MainActor isolation for thread-safe configManager access
- fix: remove invalid JSON serialization for system field in FormatTranslator
- fix: wait for keychain load before setting original state in ProviderDetailView

## Download

- [APIBypass-0.6.4.dmg](https://github.com/panando/APIBypass/releases/tag/v0.6.4)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.6.4
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.6.3

## Bug Fixes

- **Fixed layout recursion crash when selecting provider in List**: Added explicit frame constraints to `Toggle.toggleStyle(.switch)` to prevent `NSSwitch intrinsicContentSize` calculation from creating circular layout dependency in nested `ScrollView → VStack → ForEach → MappingCardView → HStack → Toggle` structure on macOS 26.5.1. Previously, clicking between providers in the sidebar caused `LayoutEngineBox.sizeThatFits` to recurse 13+ levels, corrupting heap memory and triggering `EXC_BAD_ACCESS (SIGBUS)`.

## Changelog

- fix: prevent layout recursion crash when selecting provider in List

## Download

- [APIBypass-0.6.3.dmg](https://github.com/panando/APIBypass/releases/tag/v0.6.3)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.6.3
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.6.2

## Bug Fixes

- **Fixed app activation timing**: Moved `activationPolicy` setup from `init()` to `onAppear` to ensure proper app initialization and prevent potential launch issues
- **Fixed Toggle-in-Button crash**: Moved Toggle control outside of Button to prevent SwiftUI rendering crash

## Changelog

- fix: move activationPolicy setup from init() to onAppear
- fix: move Toggle outside Button to prevent crash

## Download

- [APIBypass-0.6.2.dmg](https://github.com/panando/APIBypass/releases/tag/v0.6.2)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.6.2
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.6.1

## What's New

### Built-in Help Window
- **Comprehensive in-app help**: Added a "Help" option in the menu bar that opens a native SwiftUI help window with sidebar navigation covering:
  - Quick Start guide
  - Menu bar options explained
  - Model Mapping concepts and configuration
  - Parameter Injection and Custom Parameters
  - Claude Code Launcher usage
  - Bypass Mode details and when to use it
  - Settings overview
  - Frequently Asked Questions (FAQ)
- **Bilingual Help**: Help content automatically follows the app's current language setting (Chinese / English)

### UI Improvements
- **Improved menu grouping**: Moved "Launch Claude Code" into the same menu group as "Bypass Mode" for better logical organization

### Bug Fixes
- Clarified help documentation: reasoning mode is controlled via `enable_thinking` by default; providers using different fields should use Custom Parameters
- Fixed terminology: "API Token" → "API Key" in the Claude Code Launcher help section

## Changelog

- feat: add built-in Help window with `NavigationSplitView` and sidebar navigation
- feat: add bilingual help content for all major features
- feat: add `HelpView` with 8 sections of documentation
- ui: move "Launch Claude Code" menu item into the Bypass Mode group
- fix: clarify reasoning mode documentation (`enable_thinking` default behavior)
- fix: correct "API Token" to "API Key" in launcher help text

## Download

- [APIBypass-0.6.1.dmg](https://github.com/panando/APIBypass/releases/tag/v0.6.1)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.6.1
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.6.0

## What's New

### Bypass Mode (Pure Proxy)
- **One-click toggle**: Added a "Bypass Mode" option in the menu bar to enable pure proxy mode
- **Transparent passthrough**: When activated, the app passes all requests and responses between client and upstream without any API format conversion, while still preserving model mapping configurations (parameter injection, custom parameters, reasoning toggle, etc.)
- **Use case**: Ideal when the upstream provider natively supports the same API format as the client, eliminating unnecessary translation overhead
- **Full feature compatibility**: High concurrency remains fully supported — bypass mode only skips the format conversion step, all other features (model mapping, parameter injection, API key retrieval, streaming) continue to work normally

## Changelog

- feat: add bypass mode toggle in menu bar
- feat: implement bypass mode in HTTPServer — skips format conversion when enabled
- feat: preserve model mapping and parameter injection in bypass mode

## Download

- [APIBypass-0.6.0.dmg](https://github.com/panando/APIBypass/releases/tag/v0.6.0)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.6.0
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.5.7

## What's New

### Concurrency Performance Optimization
- **Connection limit control**: Implemented `AsyncSemaphore` to limit concurrent connections (default: 100). Returns `503 Service Unavailable` when limit is exceeded, preventing resource exhaustion.
- **Backpressure control**: New `streamWithBackpressure` method with 64KB buffer (64x increase from 1KB) and 8KB checkpoint yielding for smoother concurrent performance.
- **Local model parameter filtering**: Automatically removes 17 local-model-specific parameters (e.g., `num_ctx`, `n_gpu_layers`) that cloud APIs don't accept, preventing `400 Bad Request` errors from providers like Fireworks.

### Streaming Response Fixes
- **JSON error format fix**: Error responses in SSE streams now use proper JSON serialization instead of string concatenation, fixing `AI_JSONParseError` in clients like Cherry Studio.
- **Stream termination fix**: Added `writer.finish(nil)` call after stream completion to properly close HTTP connections, preventing clients from hanging in waiting state.

## Performance Improvements

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Buffer size | 1KB | 64KB | 64x |
| Max concurrent connections | Unlimited | 100 (configurable) | Controlled |
| Thread yielding | None | Every 8KB | Smoother |
| Byte-by-byte processing | Yes | No | Batch processing |

## Changelog

- feat: add `AsyncSemaphore` for concurrent connection limiting
- feat: implement `streamWithBackpressure` with 64KB buffer and backpressure control
- feat: filter 17 local model parameters (`num_ctx`, `n_ctx`, `n_gpu_layers`, etc.)
- fix: JSON serialization for SSE error responses (fixes `AI_JSONParseError`)
- fix: call `writer.finish(nil)` to close streaming connections properly
- perf: 64KB buffer size (was 1KB)
- perf: `Task.yield()` every 8KB for cooperative multitasking

## Download

- [APIBypass-0.5.7.dmg](https://github.com/panando/APIBypass/releases/tag/v0.5.7)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.5.7
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.5.6

## What's New

### SSE Compatibility Fix
- **Fixed SSE parsing for non-standard providers**: Resolved an issue where some API providers (e.g., MiMo) return SSE events without blank line separators, causing complete response failure. The decoder now correctly handles both standard and non-standard SSE formats.

### Extended Thinking Support
- **Anthropic → OpenAI thinking conversion**: When converting Anthropic streaming responses to OpenAI format, `thinking_delta` blocks are now mapped to OpenAI's native `reasoning_content` field, ensuring seamless display in OpenAI-compatible clients.
- **Redacted thinking handling**: `redacted_thinking` blocks are converted to a placeholder message in `reasoning_content`.

### Claude Code Launcher Improvements
- **Simplified default templates**: Reduced from 3 preset templates to 1 empty "Default" template for cleaner initial state.
- **Unified UI styling**: Terminal selection section now matches the environment variables section with consistent border styling.

## Changelog

- fix: SSE decoder compatibility with non-standard SSE format (no blank line separators)
- feat: convert Anthropic `thinking_delta` to OpenAI `reasoning_content` in streaming translation
- feat: handle `redacted_thinking` blocks in Anthropic → OpenAI conversion
- feat: add `signature_delta` handling (ignored for single-turn, needed for multi-turn continuity)
- refactor: simplify default templates to single empty "Default" template
- style: unify terminal selection section border with environment variables section
- chore: add debug logging for SSE stream processing

## Download

- [APIBypass-0.5.6.dmg](https://github.com/panando/APIBypass/releases/tag/v0.5.6)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.5.6
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

# APIBypass v0.5.3

## What's New

### Cross-Provider Model Selection in Claude Code Launcher
- **Per-model provider picker**: each model environment variable (ANTHROPIC_MODEL, OPUS, SONNET, HAIKU, SUBAGENT) now has an independent two-tier picker — first select the provider, then choose a mapping from that provider
- **Removed top-level provider selector**: the previous single provider picker at the top of the launcher is no longer needed, since each model carries its own provider context
- All five models can now route to different upstream providers simultaneously

## Changelog

- feat: two-tier model selection (provider → mapping) per model in Claude Code launcher
- feat: cross-provider model support — each env var model can target a different provider
- feat: remove redundant top-level provider picker from launcher UI
- docs: update screenshot for new launcher layout

## Download

- [APIBypass-0.5.3.dmg](https://github.com/panando/APIBypass/releases/tag/v0.5.3)

## Build from Source

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass
git checkout v0.5.3
swift build -c release
```

**Requirements**: macOS 14.0+, Swift 6.0+, Xcode 16.0+

---

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

- [v0.6.3](https://github.com/panando/APIBypass/releases/tag/v0.6.3) - Layout recursion crash fix
- [v0.6.2](https://github.com/panando/APIBypass/releases/tag/v0.6.2) - Activation fix, Toggle-in-Button crash fix
- [v0.6.1](https://github.com/panando/APIBypass/releases/tag/v0.6.1) - Built-in Help Window, UI improvements
- [v0.5.2](https://github.com/panando/APIBypass/releases/tag/v0.5.2) - OpenAI Responses API, Claude Code compatibility fixes, URL building improvements
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
