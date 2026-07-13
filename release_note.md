# APIBypass v0.9.1

## Bug Fixes

- **Provider Sidebar Reorder** — Fix drag-to-reorder in the config page's provider list landing in wrong positions. The list groups providers by API protocol (Chat Completions / Anthropic / Responses API) into separate sections, each with its own `.onMove`. SwiftUI gives `.onMove` offsets relative to that section's filtered subset, but `moveProvider` treated them as global array offsets — so reordering landed wrong in every group (including the first) whenever the stored order wasn't perfectly clustered by protocol. `moveProvider` now takes the `apiProvider` scope and remaps section-local offsets onto the group's fixed global slots (extract group → `Array.move` → backfill), keeping non-group items in place. Drag is scoped to within-group; cross-group drags clamp to the group boundary.

## Technical Changes

- `ConfigDataStore.moveProvider` gains an `apiProvider: APIProvider` parameter and uses the extract-group → `Array.move` → backfill-slots algorithm (preserves the group's occupied global slots)
- `ConfigManager.moveProvider` forwards the `apiProvider` scope
- `ConfigWindow.swift`'s three `.onMove` handlers pass `.openai` / `.anthropic` / `.responses` respectively
- Add `APIBypassTests/ProviderReorderTests.swift` with 7 cases covering within-group move (forward/backward/mixed-storage), cross-group clamp, persistence, empty-group no-op, and out-of-range source drop

---

# APIBypass v0.9.0

## New Features

- **ChatGPT.app Support** — Adapt to OpenAI's Codex.app → ChatGPT.app rename. The app is now detected, launched, and injected correctly regardless of whether the installed version is named Codex.app or ChatGPT.app.

## Bug Fixes

- **CDP Target Matching** — Fix injection failure when ChatGPT.app is installed. The previous `pickCodexTarget` logic only matched pages with "codex" in the title/URL and fell back to the first page, which could inject into the wrong target (DevTools, extension pages). Now uses precise matching: ChatGPT desktop pages are identified by exact title ("ChatGPT") plus URL whitelist (chatgpt.com, chat.openai.com, data:text/html), and the unsafe first-page fallback is removed.

## Technical Changes

- Add ChatGPT.app paths to `CodexAppLauncher.defaultCandidates` (after legacy Codex.app paths, matching CodexPlusPlus priority order)
- Add `resolveExecutableName(appURL:)` to read `CFBundleExecutable` from Info.plist instead of hardcoding "Codex"
- Add `appNameFromURL(_:)` to derive app display name from bundle path
- Update `manualLaunchCommand` to accept `appName` parameter for correct `open -a` command generation
- Extract `pickCodexTarget` as a public function in CodexRouterCore with two-pass matching (codex keyword → ChatGPT desktop → nil)
- Update localization strings to reference "Codex/ChatGPT" in detection and error messages
- Add 29 new tests covering ChatGPT detection, executable resolution, and CDP target matching

---

# APIBypass v0.8.9

## Bug Fixes

- **swift_task_dealloc Crash** — Fix a crash (`swift_task_dealloc` with "freed pointer was not the last allocation") that occurred when clicking "Launch Codex" while CodexAdaptorService was running. The crash was caused by Swift Issue #86204 — `Task.sleep(for:)` cross-module Duration specialization conflict. Replaced all `Task.sleep(for:)` calls with `Task.sleep(nanoseconds:)` to work around this Swift compiler bug.

- **Codex Not Restarting After Termination** — Fix an issue where Codex would close but fail to restart when clicking "Launch Codex". The previous fixed 800ms wait was unreliable — process exit time varies. Now polls every 200ms to detect when the process has actually exited (with 5-second timeout protection), ensuring reliable restart.

## Technical Changes

- Replace `Task.sleep(for:)` with `Task.sleep(nanoseconds:)` in three locations:
  - `CodexAppLauncher.swift` — terminate wait and debug port polling
  - `CodexAdaptorService.swift` — CDP state polling
  - `CodexAppInjector.swift` (CodexRouterCore) — monitor loop

---

# APIBypass v0.8.8

## New Features

- **Protocol Switch Restart Confirmation** — When switching communication protocol (Chat Completions ↔ Responses API) while Codex APP is running, show a confirmation dialog informing the user that a restart is required. Unsaved model changes are merged into a single dialog when applicable.

## Technical Changes

- Move config mirror file from `~/.codex/` to `~/Library/Application Support/com.apibypass.APIBypass/` for better separation from Codex APP's directory
- Add `ProtocolSwitchDecisionMaker` component with unit tests for protocol switch logic

---

# Previous Releases

## v0.8.7

### New Features

- **Verbose Logging Toggle** — Add a "Verbose" switch in Codex Adaptor's Logs tab. When disabled, only errors are logged and consecutive duplicate events are skipped, reducing log noise.

- **Automatic Parameter Error Retry** — When upstream returns a 400 error due to parameter issues (e.g., thinking budget exceeded, signature mismatch), the proxy automatically retries with corrected parameters.

### Bug Fixes

- **Model Resolution** — Fix model name resolution in Codex Adaptor to prioritize the `model` (slug) field over `displayName` when matching catalog entries, improving compatibility with Codex's identifier handling.

### Technical Changes

- Consolidate logging by removing redundant `CodexLoggingService`, using `CodexLogStore` as the single logging component with OSLog integration
- Add `ParamErrorRetry` utility for parsing upstream error responses and determining retry actions
- Improve request logging with unique request IDs for better traceability

## v0.8.6

### Bug Fixes

- **WireAPI persistence** — Fix communication protocol (Chat Completions / Responses API) setting not persisting correctly in Codex adaptor. The selection now persists across app restarts.

- **CancellationError handling** — Fix potential crash from not properly propagating CancellationError in async sleep calls.

### Technical Changes

- Add hasLoadedConfig and oldValue != newValue guards in onChange
- Use DispatchQueue.main.async to clear isHandlingProtocolSwitch flag after state updates
- Fix error handling in CodexAppLauncher, CodexAdaptorService, and CodexAppInjector
