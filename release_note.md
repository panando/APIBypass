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
