# Codex Adaptor Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate codex-adapter's Responses API proxy, reasoning config, CDP injection, and logging into APIBypass as a built-in feature accessible from the menu bar.

**Architecture:** CodexRouterCore is copied as an independent SPM library target. Server/service files from CodexRouterApp are adapted into APIBypass's source tree with logging references changed. A new CodexAdaptorService manages the proxy server lifecycle. UI is built as a single CodexAdaptorView panel. Config persists to both APIBypass's UserDefaults and ~/.codex/ files for Codex CLI compatibility.

**Tech Stack:** Swift 6.0+, SwiftUI, Hummingbird 2.0, TOMLKit, macOS 14+

---

## File Map

### Create (new files)

| File | Responsibility |
|------|----------------|
| `APIBypass/CodexRouterCore/` (13 files) | Library target — Responses↔Chat translation, reasoning, CDP, HTTP client |
| `APIBypass/Core/CodexRouter/LogTypes.swift` | LogEntry + DisplayLogLevel types (extracted from LogViewerView) |
| `APIBypass/Core/CodexRouter/CodexLogStore.swift` | In-memory ring buffer for log entries |
| `APIBypass/Core/CodexRouter/CodexLoggingService.swift` | Structured logging with OSLog + file output |
| `APIBypass/Core/CodexRouter/CodexProxyServer.swift` | Hummingbird HTTP server for Codex Adaptor |
| `APIBypass/Core/CodexRouter/CodexRequestHandler.swift` | Request handler — forwarding, transformation, streaming |
| `APIBypass/Core/CodexRouter/CodexRoutes.swift` | Route configuration for proxy endpoints |
| `APIBypass/Core/CodexRouter/CodexConfigService.swift` | ~/.codex/ config file management |
| `APIBypass/Models/CodexAdaptorConfig.swift` | Data model for Codex Adaptor configuration |
| `APIBypass/Core/CodexAdaptorService.swift` | Service managing Codex Adaptor server lifecycle |
| `APIBypass/Core/CodexConfigBridge.swift` | Bridge between APIBypass models and CodexRouterCore |
| `APIBypass/UI/Views/CodexAdaptorView.swift` | Main configuration panel UI |

### Modify (existing files)

| File | Change |
|------|--------|
| `Package.swift` | Add TOMLKit dependency, CodexRouterCore target |
| `APIBypass/UI/MenuBarView.swift` | Add "Codex Adaptor" menu item + window opener |
| `APIBypass/APIBypassApp.swift` | Add CodexAdaptorService state object |
| `APIBypass/Core/LocalizationManager.swift` | Add ~30 localization keys for Codex Adaptor |
| `APIBypass/UI/HelpView.swift` | Add Codex Adaptor help section |

---

### Task 1: Copy CodexRouterCore and Update Package.swift

**Files:**
- Create: `APIBypass/CodexRouterCore/` (entire directory, 13 files)
- Modify: `Package.swift`

- [ ] **Step 1: Copy CodexRouterCore source files**

```bash
cp -r /Users/panando/ClaudeCode/codex-adapter/Sources/CodexRouterCore /Users/panando/ClaudeCode/APIbypass/APIBypass/CodexRouterCore
```

Verify the copy:
```bash
ls -la /Users/panando/ClaudeCode/APIbypass/APIBypass/CodexRouterCore/
ls -la /Users/panando/ClaudeCode/APIbypass/APIBypass/CodexRouterCore/CDP/
ls -la /Users/panando/ClaudeCode/APIbypass/APIBypass/CodexRouterCore/Models/
ls -la /Users/panando/ClaudeCode/APIbypass/APIBypass/CodexRouterCore/Networking/
ls -la /Users/panando/ClaudeCode/APIbypass/APIBypass/CodexRouterCore/Transformers/
```

Expected: 13 files across 4 subdirectories (CDP: 4, Models: 2, Networking: 2, Transformers: 5)

- [ ] **Step 2: Update Package.swift**

Replace the entire content of `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "APIBypass",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "APIBypass", targets: ["APIBypass"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "CodexRouterCore",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "APIBypass/CodexRouterCore"
        ),
        .executableTarget(
            name: "APIBypass",
            dependencies: [
                "CodexRouterCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdRouter", package: "hummingbird")
            ],
            path: "APIBypass"
        ),
        .testTarget(
            name: "APIBypassTests",
            dependencies: ["APIBypass"],
            path: "APIBypassTests"
        )
    ]
)
```

- [ ] **Step 3: Verify build compiles**

```bash
cd /Users/panando/ClaudeCode/APIbypass && xcodebuild -scheme APIBypass -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED (the copied CodexRouterCore files should compile as a library target)

- [ ] **Step 4: Commit**

```bash
git add APIBypass/CodexRouterCore/ Package.swift
git commit -m "feat: add CodexRouterCore library target from codex-adapter"
```

---

### Task 2: Create Logging Infrastructure

**Files:**
- Create: `APIBypass/Core/CodexRouter/LogTypes.swift`
- Create: `APIBypass/Core/CodexRouter/CodexLogStore.swift`
- Create: `APIBypass/Core/CodexRouter/CodexLoggingService.swift`

- [ ] **Step 1: Create LogTypes.swift**

```bash
mkdir -p /Users/panando/ClaudeCode/APIbypass/APIBypass/Core/CodexRouter
```

Create `APIBypass/Core/CodexRouter/LogTypes.swift`:

```swift
import SwiftUI

/// A single log entry for the Codex Adaptor log viewer.
struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: String
    let level: DisplayLogLevel
    let message: String

    init(level: DisplayLogLevel, message: String) {
        self.timestamp = ISO8601DateFormatter().string(from: Date())
        self.level = level
        self.message = message
    }
}

/// Log level with color coding for the UI.
enum DisplayLogLevel: String, Sendable {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"

    var color: Color {
        switch self {
        case .debug: return .secondary
        case .info:  return .blue
        case .warn:  return .orange
        case .error: return .red
        }
    }
}
```

- [ ] **Step 2: Create CodexLogStore.swift**

Create `APIBypass/Core/CodexRouter/CodexLogStore.swift`:

```swift
import Foundation

/// In-memory ring buffer for Codex Adaptor log entries. Observable by log viewer UI.
final class CodexLogStore: ObservableObject, @unchecked Sendable {
    static let shared = CodexLogStore()

    @Published private(set) var entries: [LogEntry] = []
    private let maxEntries = 2000
    private let lock = NSLock()

    private init() {}

    /// Thread-safe append from any context.
    func append(level: DisplayLogLevel, message: String) {
        let entry = LogEntry(level: level, message: message)
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        lock.unlock()
    }

    /// Convenience: append info-level message.
    func info(_ message: String) {
        append(level: .info, message: message)
    }

    /// Clear all entries.
    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}
```

- [ ] **Step 3: Create CodexLoggingService.swift**

Create `APIBypass/Core/CodexRouter/CodexLoggingService.swift`:

```swift
import Foundation
import OSLog

/// Log level for the Codex Adaptor logging service.
enum CodexLogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    static func < (lhs: CodexLogLevel, rhs: CodexLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }

    var prefix: String {
        switch self {
        case .debug: return "[DEBUG]"
        case .info: return "[INFO]"
        case .warning: return "[WARN]"
        case .error: return "[ERROR]"
        }
    }
}

/// Log category for organizing log messages.
enum CodexLogCategory: String, Sendable {
    case proxy = "Proxy"
    case provider = "Provider"
    case transformer = "Transformer"
    case config = "Config"
    case general = "General"
}

/// Structured logging service for Codex Adaptor.
actor CodexLoggingService {
    static let shared = CodexLoggingService()

    private let logger = Logger(subsystem: "com.apibypass.codexadaptor", category: "General")
    private var minimumLevel: CodexLogLevel = .info
    private var logFileURL: URL?
    private var fileHandle: FileHandle?

    private init() {}

    func setMinimumLevel(_ level: CodexLogLevel) {
        minimumLevel = level
    }

    func enableFileLogging(to path: String? = nil) throws {
        let logPath = path ?? defaultLogPath()
        logFileURL = URL(fileURLWithPath: logPath)

        let directory = logFileURL!.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        fileHandle = try FileHandle(forWritingTo: logFileURL!)
    }

    func disableFileLogging() {
        fileHandle?.closeFile()
        fileHandle = nil
        logFileURL = nil
    }

    func defaultLogPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.codex/logs/proxy.log"
    }

    func info(
        _ message: String,
        category: CodexLogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }

    func error(
        _ message: String,
        category: CodexLogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }

    private func log(
        _ message: String,
        level: CodexLogLevel,
        category: CodexLogCategory,
        file: String,
        function: String,
        line: Int
    ) {
        guard level >= minimumLevel else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "\(timestamp) \(level.prefix) [\(category.rawValue)] \(fileName):\(line) - \(message)"

        logger.log(level: level.osLogType, "\(logMessage)")

        // Also append to CodexLogStore for UI
        let displayLevel: DisplayLogLevel
        switch level {
        case .debug: displayLevel = .debug
        case .info: displayLevel = .info
        case .warning: displayLevel = .warn
        case .error: displayLevel = .error
        }
        CodexLogStore.shared.append(level: displayLevel, message: message)

        if let handle = fileHandle {
            let data = (logMessage + "\n").data(using: .utf8)!
            handle.write(data)
        }
    }
}
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/panando/ClaudeCode/APIbypass && xcodebuild -scheme APIBypass -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add APIBypass/Core/CodexRouter/LogTypes.swift APIBypass/Core/CodexRouter/CodexLogStore.swift APIBypass/Core/CodexRouter/CodexLoggingService.swift
git commit -m "feat: add Codex Adaptor logging infrastructure"
```

---

### Task 3: Adapt Server Files

**Files:**
- Create: `APIBypass/Core/CodexRouter/CodexProxyServer.swift`
- Create: `APIBypass/Core/CodexRouter/CodexRequestHandler.swift`
- Create: `APIBypass/Core/CodexRouter/CodexRoutes.swift`

- [ ] **Step 1: Create CodexProxyServer.swift**

Create `APIBypass/Core/CodexRouter/CodexProxyServer.swift`. This is adapted from `ProxyServer.swift` with these changes:
- `import CodexRouterCore` stays (it's now a local module)
- No other changes needed — ProxyServer doesn't reference LogStore directly

```swift
import Foundation
import Hummingbird
import CodexRouterCore

/// HTTP proxy server for Codex Adaptor.
/// Reads configuration directly from ~/.codex/config.toml
final class CodexProxyServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var port: Int = 15721

    private var app: Application<RouterResponder<BasicRequestContext>>?

    init() {}

    func start(
        port: Int = 15721,
        settingsHandler: @escaping () async -> (Int, String, String)
    ) async throws {
        self.port = port

        let router = Router()
        CodexRoutes.configure(router: router, settingsHandler: settingsHandler)

        let responder = router.buildResponder()
        let app = Application(
            responder: responder,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )

        self.app = app

        Task {
            do {
                try await app.run()
            } catch {
                print("[CodexAdaptor] Server error: \(error)")
            }
        }

        await MainActor.run {
            self.isRunning = true
        }

        CodexLogStore.shared.info("[CodexAdaptor] Server started on port \(port)")
    }

    func stop() async {
        self.app = nil

        await MainActor.run {
            self.isRunning = false
        }

        CodexLogStore.shared.info("[CodexAdaptor] Server stopped")
    }
}
```

- [ ] **Step 2: Create CodexRoutes.swift**

Create `APIBypass/Core/CodexRouter/CodexRoutes.swift`. Adapted from `Routes.swift` — no changes needed since it references `RequestHandler` (we'll rename to `CodexRequestHandler`):

```swift
import Foundation
import Hummingbird
import CodexRouterCore

/// Route configuration for Codex Adaptor proxy server.
enum CodexRoutes {
    static func configure(
        router: Router<BasicRequestContext>,
        settingsHandler: @escaping () async -> (Int, String, String)
    ) {
        let requestHandler = CodexRequestHandler()

        // Health check
        router.get("/health") { _, _ in
            return Response(
                status: .ok,
                body: .init(byteBuffer: ByteBuffer(string: #"{"status":"healthy"}"#))
            )
        }

        // CDP injection settings endpoint (polled by injected JS)
        router.get("/settings/get") { _, _ in
            let (status, contentType, body) = await settingsHandler()
            var headers = HTTPFields()
            headers[.contentType] = contentType
            return Response(
                status: .init(code: status, reasonPhrase: status == 200 ? "OK" : "Error"),
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(string: body))
            )
        }

        // Models endpoint - proxy to upstream
        router.get("/v1/models") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .models)
        }

        // Chat Completions (with /v1 prefix)
        router.post("/v1/chat/completions") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .chatCompletions)
        }

        // Responses API (with /v1 prefix)
        router.post("/v1/responses") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responses)
        }

        // Responses Compact (with /v1 prefix)
        router.post("/v1/responses/compact") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responsesCompact)
        }

        // Routes without /v1 prefix (for Codex compatibility)
        router.get("/models") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .models)
        }

        router.post("/chat/completions") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .chatCompletions)
        }

        router.post("/responses") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responses)
        }

        router.post("/responses/compact") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responsesCompact)
        }
    }
}
```

- [ ] **Step 3: Create CodexRequestHandler.swift**

Create `APIBypass/Core/CodexRouter/CodexRequestHandler.swift`. This is the largest file — adapted from `RequestHandler.swift` with these changes:
- Rename class to `CodexRequestHandler`
- Replace all `LogStore.shared.info(...)` with `CodexLogStore.shared.info(...)`
- Everything else stays the same

Read the original file from `/Users/panando/ClaudeCode/codex-adapter/Sources/CodexRouterApp/Server/RequestHandler.swift` and copy it with these modifications:
1. Change `public actor RequestHandler` → `actor CodexRequestHandler`
2. Change all `LogStore.shared.info(` → `CodexLogStore.shared.info(`
3. Remove `public` access modifiers (not needed within the same module)

- [ ] **Step 4: Verify build**

```bash
cd /Users/panando/ClaudeCode/APIbypass && xcodebuild -scheme APIBypass -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add APIBypass/Core/CodexRouter/CodexProxyServer.swift APIBypass/Core/CodexRouter/CodexRequestHandler.swift APIBypass/Core/CodexRouter/CodexRoutes.swift
git commit -m "feat: add Codex Adaptor server components (proxy, routes, request handler)"
```

---

### Task 4: Adapt CodexConfigService

**Files:**
- Create: `APIBypass/Core/CodexRouter/CodexConfigService.swift`

- [ ] **Step 1: Create CodexConfigService.swift**

Copy from `/Users/panando/ClaudeCode/codex-adapter/Sources/CodexRouterApp/Services/CodexConfigService.swift` with these changes:
1. Remove `import CodexRouterCore` (CodexRouterCore is now a dependency of the same target, but since this file is in the APIBypass target which depends on CodexRouterCore, keep the import)
2. Remove `public` access modifiers from all types and methods (they're used within the APIBypass target)
3. Keep `import TOMLKit` and `import Foundation`

The file contains these types that will be used by other files:
- `CodexConfigService` (class)
- `CodexModelProvider` (struct)
- `UpstreamProvider` (struct)
- `ProviderStore` (struct, internal)
- `ProviderMetaEntry` (struct, internal)
- `CodexConfigError` (enum)

Copy the file as-is, just change access modifiers from `public` to `internal` (or remove `public`).

- [ ] **Step 2: Verify build**

```bash
cd /Users/panando/ClaudeCode/APIbypass && xcodebuild -scheme APIBypass -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add APIBypass/Core/CodexRouter/CodexConfigService.swift
git commit -m "feat: add Codex Adaptor config service for ~/.codex/ file management"
```

---

### Task 5: Create CodexAdaptorConfig Data Model

**Files:**
- Create: `APIBypass/Models/CodexAdaptorConfig.swift`

- [ ] **Step 1: Create CodexAdaptorConfig.swift**

Create `APIBypass/Models/CodexAdaptorConfig.swift`:

```swift
import Foundation
import CodexRouterCore

/// Configuration for the Codex Adaptor feature, persisted in APIBypass's UserDefaults.
struct CodexAdaptorConfig: Codable, Equatable {
    var port: Int = 15721
    var wireAPI: WireAPI = .chat
    var reasoningOverrideEnabled: Bool = false
    var reasoningConfig: ReasoningConfig?
    var customModels: [CustomModelEntry] = []
    var cdpSettings: CDPInjectionSettings = CDPInjectionSettings()
    var cdpDebugPort: UInt16 = 9222

    enum WireAPI: String, Codable, CaseIterable {
        case chat = "chat"
        case responses = "responses"

        var displayName: String {
            switch self {
            case .chat: return "Chat Completions"
            case .responses: return "Responses API"
            }
        }
    }
}

/// A custom model entry mapping an alias to an APIBypass model mapping.
struct CustomModelEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var alias: String
    var modelMappingId: UUID
    var contextWindow: UInt64 = 128000
}
```

- [ ] **Step 2: Create CodexAdaptorConfigStore**

Add to the same file or create a separate file `APIBypass/Core/CodexAdaptorConfigStore.swift`:

```swift
import Foundation

/// Persistence layer for CodexAdaptorConfig using UserDefaults.
actor CodexAdaptorConfigStore {
    static let shared = CodexAdaptorConfigStore()

    private let userDefaultsKey = "com.apibypass.codexAdaptor"
    private var cached: CodexAdaptorConfig?

    private init() {}

    func load() -> CodexAdaptorConfig {
        if let cached { return cached }
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(CodexAdaptorConfig.self, from: data) else {
            let defaultConfig = CodexAdaptorConfig()
            cached = defaultConfig
            return defaultConfig
        }
        cached = config
        return config
    }

    func save(_ config: CodexAdaptorConfig) {
        cached = config
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/panando/ClaudeCode/APIbypass && xcodebuild -scheme APIBypass -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add APIBypass/Models/CodexAdaptorConfig.swift APIBypass/Core/CodexAdaptorConfigStore.swift
git commit -m "feat: add Codex Adaptor config data model and persistence"
```

---

### Task 6: Create CodexAdaptorService

**Files:**
- Create: `APIBypass/Core/CodexAdaptorService.swift`

- [ ] **Step 1: Create CodexAdaptorService.swift**

Create `APIBypass/Core/CodexAdaptorService.swift`:

```swift
import Foundation
import SwiftUI
import CodexRouterCore

/// Service managing the Codex Adaptor proxy server lifecycle.
@MainActor
final class CodexAdaptorService: ObservableObject {
    @Published var isRunning = false
    @Published var port: Int = 15721

    private var server: CodexProxyServer?
    private var injector: CodexAppInjector?

    init() {
        Task {
            let config = await CodexAdaptorConfigStore.shared.load()
            port = config.port
        }
    }

    func start() async throws {
        let config = await CodexAdaptorConfigStore.shared.load()
        port = config.port

        // Sync config to ~/.codex/ files
        try await syncCodexConfig(config: config)

        let server = CodexProxyServer()
        self.server = server

        // Start CDP injector if enhancements enabled
        if config.cdpSettings.enhancementsEnabled {
            let inj = CodexAppInjector(
                debugPort: config.cdpDebugPort,
                settings: config.cdpSettings
            )
            self.injector = inj
            await inj.start()
        }

        try await server.start(port: config.port) { [weak self] in
            await self?.handleSettingsGet() ?? (200, "application/json", "{}")
        }

        isRunning = true
        CodexLogStore.shared.info("[CodexAdaptor] Service started on port \(config.port)")
    }

    func stop() async {
        await injector?.stop()
        injector = nil

        await server?.stop()
        server = nil

        isRunning = false
        CodexLogStore.shared.info("[CodexAdaptor] Service stopped")
    }

    func updateConfig(_ config: CodexAdaptorConfig) async throws {
        await CodexAdaptorConfigStore.shared.save(config)
        try await syncCodexConfig(config: config)

        // Update CDP settings if running
        if let inj = injector {
            await inj.updateSettings(config.cdpSettings)
        }

        port = config.port
    }

    func pushInjectionSettings() async {
        guard let inj = injector else { return }
        let config = await CodexAdaptorConfigStore.shared.load()
        await inj.updateSettings(config.cdpSettings)
    }

    func currentInjectionSettings() async -> CDPInjectionSettings {
        let config = await CodexAdaptorConfigStore.shared.load()
        return config.cdpSettings
    }

    func handleSettingsGet() async -> (Int, String, String) {
        if let inj = injector {
            return inj.handleSettingsGet()
        }
        return (200, "application/json", "{}")
    }

    /// Sync APIBypass Codex Adaptor config to ~/.codex/ files for Codex CLI compatibility.
    private func syncCodexConfig(config: CodexAdaptorConfig) async throws {
        let configService = CodexConfigService.shared

        // Build a CodexModelProvider from the config
        let provider = CodexModelProvider(
            id: "apibypass",
            name: "APIBypass",
            baseURL: "http://127.0.0.1:\(port)/v1",
            upstreamWireAPI: config.wireAPI.rawValue,
            bearerToken: "1234",
            modelCatalog: buildModelCatalog(from: config),
            reasoningConfig: config.reasoningOverrideEnabled ? config.reasoningConfig : nil,
            enabled: true
        )

        try configService.saveProvider(provider)
        try configService.switchProvider(to: "apibypass")
    }

    private func buildModelCatalog(from config: CodexAdaptorConfig) -> ModelCatalog? {
        guard !config.customModels.isEmpty else { return nil }
        let entries = config.customModels.map { entry in
            ModelCatalogEntry(
                model: entry.alias,
                displayName: entry.alias,
                contextWindow: entry.contextWindow
            )
        }
        return ModelCatalog(models: entries)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/panando/ClaudeCode/APIbypass && xcodebuild -scheme APIBypass -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add APIBypass/Core/CodexAdaptorService.swift
git commit -m "feat: add Codex Adaptor service with lifecycle management"
```

---

### Task 7: Create CodexConfigBridge

**Files:**
- Create: `APIBypass/Core/CodexConfigBridge.swift`

- [ ] **Step 1: Create CodexConfigBridge.swift**

Create `APIBypass/Core/CodexConfigBridge.swift`:

```swift
import Foundation
import CodexRouterCore

/// Bridges APIBypass's model mappings to CodexRouterCore's model catalog system.
struct CodexConfigBridge {
    /// Extract all available model names from APIBypass's ConfigManager for the dropdown.
    static func availableModelNames(from configManager: ConfigManager) -> [String] {
        configManager.mappings
            .filter { $0.isEnabled }
            .map { $0.incomingModel }
            .sorted()
    }

    /// Get all model mappings from APIBypass's ConfigManager.
    static func availableMappings(from configManager: ConfigManager) -> [ModelMapping] {
        configManager.mappings.filter { $0.isEnabled }
    }

    /// Resolve a CustomModelEntry to the actual model name via APIBypass's mappings.
    static func resolveModelName(entry: CustomModelEntry, configManager: ConfigManager) -> String? {
        configManager.mappings.first { $0.id == entry.modelMappingId }?.incomingModel
    }

    /// Build a ModelCatalog from custom model entries for Codex's model picker.
    static func buildModelCatalog(
        from entries: [CustomModelEntry],
        configManager: ConfigManager
    ) -> ModelCatalog {
        let catalogEntries = entries.compactMap { entry -> ModelCatalogEntry? in
            guard let mapping = configManager.mappings.first(where: { $0.id == entry.modelMappingId }) else {
                return nil
            }
            return ModelCatalogEntry(
                model: entry.alias,
                displayName: entry.alias,
                contextWindow: entry.contextWindow
            )
        }
        return ModelCatalog(models: catalogEntries)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/panando/ClaudeCode/APIbypass && xcodebuild -scheme APIBypass -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add APIBypass/Core/CodexConfigBridge.swift
git commit -m "feat: add Codex Config Bridge for model mapping integration"
```

---

### Task 8: Create CodexAdaptorView

**Files:**
- Create: `APIBypass/UI/Views/CodexAdaptorView.swift`

- [ ] **Step 1: Create CodexAdaptorView.swift**

Create `APIBypass/UI/Views/CodexAdaptorView.swift`. This is a new SwiftUI view with these sections:
1. Service control (start/stop, port, status)
2. Communication protocol (wire API picker)
3. Reasoning configuration (override toggle, auto-detect, param pickers)
4. Custom models (table with alias, model dropdown from APIBypass, context window)
5. Codex Enhancements (CDP toggles, debug port)
6. Logs (real-time log viewer with filter, copy, export, clear)

The view receives `configManager: ConfigManager` and `codexAdaptor: CodexAdaptorService` as parameters. It manages its own local state for the config form, with save/load to `CodexAdaptorConfigStore`.

Key implementation details:
- Model dropdown uses `CodexConfigBridge.availableModelNames(from:)` for data
- Start/Stop buttons call `codexAdaptor.start()` / `codexAdaptor.stop()`
- Config changes call `codexAdaptor.updateConfig()` on save
- Log section uses `CodexLogStore.shared` for entries
- Reasoning "Auto Detect" button calls `ReasoningConfig.infer()` with a provider name/URL

- [ ] **Step 2: Verify build**

```bash
cd /Users/panando/ClaudeCode/APIbypass && xcodebuild -scheme APIBypass -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add APIBypass/UI/Views/CodexAdaptorView.swift
git commit -m "feat: add Codex Adaptor configuration UI"
```

---

### Task 9: Modify MenuBarView and APIBypassApp

**Files:**
- Modify: `APIBypass/UI/MenuBarView.swift`
- Modify: `APIBypass/APIBypassApp.swift`

- [ ] **Step 1: Add Codex Adaptor menu item to MenuBarView**

In `MenuBarView.swift`, add after the "Launch Claude Code" button (line 37) and before the Divider (line 39):

```swift
Button(L10n.t("codex_adaptor")) {
    openCodexAdaptorWindow()
}
```

Add the `codexAdaptor` parameter to the struct and the window opener method:

```swift
struct MenuBarView: View {
    let configManager: ConfigManager
    let codexAdaptor: CodexAdaptorService  // ADD THIS
    @Binding var isRunning: Bool
    let port: Int
    let onStart: () -> Void
    let onStop: () -> Void
    // ... rest stays the same
```

Add the window opener method (following the same pattern as `openLaunchClaudeCodeWindow`):

```swift
private func openCodexAdaptorWindow() {
    NSApplication.shared.activate(ignoringOtherApps: true)

    if let existingWindow = NSApplication.shared.windows.first(where: {
        $0.identifier?.rawValue == "codex-adaptor-window"
    }) {
        existingWindow.makeKeyAndOrderFront(nil)
        return
    }

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 700, height: 750),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = L10n.t("codex_adaptor")
    window.identifier = NSUserInterfaceItemIdentifier("codex-adaptor-window")
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: CodexAdaptorView(
        configManager: configManager,
        codexAdaptor: codexAdaptor
    ))
    window.center()
    window.makeKeyAndOrderFront(nil)
}
```

- [ ] **Step 2: Add CodexAdaptorService to APIBypassApp**

In `APIBypassApp.swift`, add:

```swift
@StateObject private var codexAdaptor = CodexAdaptorService()
```

Update the `MenuBarView` instantiation to pass `codexAdaptor`:

```swift
MenuBarView(
    configManager: configManager,
    codexAdaptor: codexAdaptor,  // ADD THIS
    isRunning: $isRunning,
    port: server?.port ?? ...,
    onStart: startServer,
    onStop: stopServer
)
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/panando/ClaudeCode/APIbypass && xcodebuild -scheme APIBypass -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add APIBypass/UI/MenuBarView.swift APIBypass/APIBypassApp.swift
git commit -m "feat: integrate Codex Adaptor into menu bar and app lifecycle"
```

---

### Task 10: Add Localization Keys

**Files:**
- Modify: `APIBypass/Core/LocalizationManager.swift`

- [ ] **Step 1: Add Codex Adaptor localization keys**

Add these entries to the `dict` dictionary in `LocalizationManager.swift`:

```swift
// Codex Adaptor
"codex_adaptor": [.chinese: "Codex Adaptor", .english: "Codex Adaptor"],
"codex_service": [.chinese: "服务", .english: "Service"],
"codex_start": [.chinese: "启动", .english: "Start"],
"codex_stop": [.chinese: "停止", .english: "Stop"],
"codex_port": [.chinese: "端口", .english: "Port"],
"codex_status_running": [.chinese: "运行中", .english: "Running"],
"codex_status_stopped": [.chinese: "已停止", .english: "Stopped"],
"codex_wire_api": [.chinese: "通信协议", .english: "Communication Protocol"],
"codex_reasoning": [.chinese: "推理配置", .english: "Reasoning Configuration"],
"codex_override_reasoning": [.chinese: "覆盖推理配置", .english: "Override Reasoning Config"],
"codex_auto_detect": [.chinese: "自动检测", .english: "Auto Detect"],
"codex_thinking_param": [.chinese: "思考参数", .english: "Thinking Param"],
"codex_effort_param": [.chinese: "Effort 参数", .english: "Effort Param"],
"codex_effort_value": [.chinese: "Effort 值映射", .english: "Effort Value"],
"codex_output_format": [.chinese: "输出格式", .english: "Output Format"],
"codex_custom_models": [.chinese: "自定义模型", .english: "Custom Models"],
"codex_model_alias": [.chinese: "别名", .english: "Alias"],
"codex_model_from_apibypass": [.chinese: "模型（来自 APIBypass）", .english: "Model (from APIBypass)"],
"codex_context_window": [.chinese: "上下文窗口", .english: "Context Window"],
"codex_add_model": [.chinese: "添加模型", .english: "Add Model"],
"codex_enhancements": [.chinese: "Codex 增强", .english: "Codex Enhancements"],
"codex_plugin_unlock": [.chinese: "插件入口解锁", .english: "Plugin Entry Unlock"],
"codex_marketplace_unlock": [.chinese: "市场解锁", .english: "Marketplace Unlock"],
"codex_force_install": [.chinese: "强制安装插件", .english: "Force Plugin Install"],
"codex_debug_port": [.chinese: "调试端口", .english: "Debug Port"],
"codex_logs": [.chinese: "日志", .english: "Logs"],
"codex_clear_logs": [.chinese: "清除", .english: "Clear"],
"codex_export_logs": [.chinese: "导出", .english: "Export"],
"codex_filter": [.chinese: "过滤", .english: "Filter"],
"codex_auto_scroll": [.chinese: "自动滚动", .english: "Auto Scroll"],
"codex_copy_all": [.chinese: "复制全部", .english: "Copy All"],
"codex_copied": [.chinese: "已复制", .english: "Copied"],
"codex_entries": [.chinese: "条记录", .english: "entries"],
"help_codex_adaptor": [.chinese: "Codex Adaptor", .english: "Codex Adaptor"],
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/panando/ClaudeCode/APIbypass && xcodebuild -scheme APIBypass -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add APIBypass/Core/LocalizationManager.swift
git commit -m "feat: add Codex Adaptor localization keys (en/zh)"
```

---

### Task 11: Update HelpView

**Files:**
- Modify: `APIBypass/UI/HelpView.swift`

- [ ] **Step 1: Add Codex Adaptor help section**

Add `.codexAdaptor` case to the `HelpSection` enum:

```swift
enum HelpSection: String, CaseIterable, Identifiable {
    case quickStart, menuBar, modelMapping, parameterInjection, launcher, bypassMode, codexAdaptor, settings, faq
    // ...
    var titleKey: String {
        // ... existing cases
        case .codexAdaptor: return "help_codex_adaptor"
    }
}
```

Add the content builder case and content view for the Codex Adaptor section, covering:
- What it does (Responses API proxy for Codex CLI)
- How to configure (wire API, reasoning, custom models)
- How to use (start service → point Codex CLI to `http://127.0.0.1:15721/v1`)
- CDP enhancements explanation

- [ ] **Step 2: Verify build**

```bash
cd /Users/panando/ClaudeCode/APIbypass && xcodebuild -scheme APIBypass -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add APIBypass/UI/HelpView.swift
git commit -m "feat: add Codex Adaptor help section"
```

---

### Task 12: Final Build Verification and Cleanup

- [ ] **Step 1: Full build verification**

```bash
cd /Users/panando/ClaudeCode/APIbypass && xcodebuild -scheme APIBypass -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED with no warnings related to new code

- [ ] **Step 2: Verify no import issues**

Check that all files that use CodexRouterCore types have `import CodexRouterCore`:
```bash
grep -rL "import CodexRouterCore" APIBypass/Core/CodexRouter/ APIBypass/Core/CodexAdaptor*.swift APIBypass/Models/CodexAdaptorConfig.swift APIBypass/UI/Views/CodexAdaptorView.swift 2>/dev/null
```

Expected: No output (all files that need the import have it)

- [ ] **Step 3: Verify localization completeness**

Check that all `L10n.t("codex_...")` calls have corresponding entries in the dict:
```bash
grep -oh 'L10n.t("codex_[^"]*")' APIBypass/UI/Views/CodexAdaptorView.swift APIBypass/UI/MenuBarView.swift | sort -u
```

Cross-reference with LocalizationManager.swift entries.

- [ ] **Step 4: Commit any final fixes**

```bash
git add -A && git commit -m "fix: final cleanup for Codex Adaptor integration"
```

---

### Task 13: Update Documentation

**Files:**
- Modify: `RELEASE_NOTES.md`
- Modify: `README.md`
- Modify: `README_CN.md`

- [ ] **Step 1: Add release notes for v0.7.0**

Add a new section at the top of `RELEASE_NOTES.md`:

```markdown
## v0.7.0

### New Features
- **Codex Adaptor**: Integrated codex-adapter as a built-in feature. Launch from menu bar "Codex Adaptor" to run a Responses API proxy for OpenAI Codex CLI, translating Responses API to Chat Completions format.
- **Reasoning Configuration**: Auto-detect and configure reasoning parameters (thinking, effort) for different providers (DeepSeek, OpenRouter, SiliconFlow, etc.)
- **Custom Models**: Define custom model aliases that map to APIBypass's model mappings, with a dropdown selector.
- **CDP Enhancements**: Plugin entry unlock, marketplace unlock, and force plugin install for Codex Electron app.
- **Real-time Logs**: Built-in log viewer with filtering, copy, export, and clear functionality.
```

- [ ] **Step 2: Update README.md and README_CN.md**

Add "Codex Adaptor" to the features section in both READMEs, documenting:
- What it does
- How to access it (menu bar)
- Communication protocol options
- Custom model configuration

- [ ] **Step 3: Commit**

```bash
git add RELEASE_NOTES.md README.md README_CN.md
git commit -m "docs: add Codex Adaptor documentation to release notes and README"
```
