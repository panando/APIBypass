# Codex Adaptor Integration Design

**Date:** 2026-06-13
**Status:** Approved
**Scope:** Integrate codex-adapter project into APIBypass as a built-in feature

## Background

codex-adapter is a standalone macOS menu bar app that acts as a local HTTP proxy between OpenAI Codex CLI and any OpenAI-compatible upstream API provider. It translates Codex's Responses API calls into Chat Completions API format. The user wants to embed this functionality directly into APIBypass, reusing APIBypass's provider/model infrastructure.

**Data flow:**
```
Codex CLI  →  Codex Adaptor (:15721)  →  APIBypass (:8390)  →  Upstream Provider
```

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Integration approach | Copy CodexRouterCore as independent SPM target | Self-contained, codex-adapter no longer maintained separately |
| Config storage | ~/.codex/ files (TOML + JSON) | Codex CLI reads config from ~/.codex/config.toml |
| APIBypass internal config | UserDefaults key `"com.apibypass.codexAdaptor"` | Consistent with existing APIBypass config pattern |
| CDP injection | Included | User requested |
| Logging | Included | User requested |

## 1. Project Structure

### Package.swift Changes

Add TOMLKit dependency and CodexRouterCore target:

```swift
let package = Package(
    name: "APIBypass",
    platforms: [.macOS(.v14)],
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

### Directory Structure

```
APIBypass/
├── CodexRouterCore/              ← Copied from codex-adapter/Sources/CodexRouterCore
│   ├── CDP/
│   │   ├── CDPClient.swift
│   │   ├── CDPInjectionScript.swift
│   │   ├── CDPTypes.swift
│   │   └── CodexAppInjector.swift
│   ├── Models/
│   │   ├── ModelCatalog.swift
│   │   └── ReasoningConfig.swift
│   ├── Networking/
│   │   └── ProxyRequest.swift
│   └── Transformers/
│       ├── ChatToResponsesTransformer.swift
│       ├── SSEStreamTransformer.swift
│       └── ...
├── Core/
│   ├── CodexAdaptorService.swift  ← NEW: server lifecycle management
│   ├── CodexConfigBridge.swift    ← NEW: bridge APIBypass models to CodexRouterCore
│   ├── HTTPServer.swift           (existing)
│   ├── ConfigManager.swift        (existing)
│   ├── ConfigDataStore.swift      (existing)
│   ├── FormatTranslator.swift     (existing)
│   ├── ProxyEngine.swift          (existing)
│   └── ...
├── Models/
│   └── ... (existing)
└── UI/
    ├── MenuBarView.swift          ← MODIFIED: add Codex Adaptor menu item
    └── Views/
        ├── CodexAdaptorView.swift ← NEW: main configuration panel
        └── ... (existing)
```

## 2. Menu Bar Integration

### MenuBarView.swift Modifications

Add "Codex Adaptor" menu item below "Launch Claude Code", within the same Divider group:

```
┌─────────────────────────────┐
│ 🟢 Server running           │
│    Port: 8390               │
│─────────────────────────────│
│ ☐ Bypass Mode               │
│─────────────────────────────│
│ ▶ Launch Claude Code        │  ← existing
│ ▶ Codex Adaptor             │  ← NEW, same group
│─────────────────────────────│
│ Configure...                │
│ Settings...                 │
│ Help...                     │
│─────────────────────────────│
│ Start/Stop Server           │
│─────────────────────────────│
│ Quit                        │
└─────────────────────────────┘
```

Window identifier: `"codex-adaptor-window"`

The menu item opens a standalone NSWindow hosting `CodexAdaptorView`.

## 3. Codex Adaptor UI (CodexAdaptorView.swift)

### Layout

```
┌──────────────────────────────────────────────────┐
│  Codex Adaptor                                    │
│──────────────────────────────────────────────────│
│                                                    │
│  Service                                           │
│  ┌──────────────────────────────────────────────┐ │
│  │  [▶ Start/■ Stop]  Port: [15721]             │ │
│  │  Status: Running / Stopped                    │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  Communication Protocol                            │
│  ┌──────────────────────────────────────────────┐ │
│  │  Wire API: (•) Chat Completions               │ │
│  │            ( ) Responses API                   │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  Reasoning Configuration                           │
│  ┌──────────────────────────────────────────────┐ │
│  │  ☑ Override Reasoning Config                  │ │
│  │  [Auto Detect]                                │ │
│  │  Thinking Param:  [enable_thinking ▾]         │ │
│  │  Effort Param:    [reasoning_effort ▾]        │ │
│  │  Effort Value:    [deepseek ▾]                │ │
│  │  Output Format:   [reasoning_content ▾]       │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  Custom Models                                     │
│  ┌──────────────────────────────────────────────┐ │
│  │  Alias         │ Model (from APIBypass) │ Ctx │ │
│  │  DeepSeek V3   │ deepseek-chat ▾       │ 128k│ │
│  │  Qwen Max      │ qwen-max ▾            │ 128k│ │
│  │  [+ Add Model]                            │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  Codex Enhancements (CDP)                          │
│  ┌──────────────────────────────────────────────┐ │
│  │  ☑ Plugin Entry Unlock                        │ │
│  │  ☑ Marketplace Unlock                         │ │
│  │  ☑ Force Plugin Install                       │ │
│  │  Debug Port: [9222]                           │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  Logs                                    [Clear]  │
│  ┌──────────────────────────────────────────────┐ │
│  │  [Real-time log stream with filtering,        │ │
│  │   copy, export to file, clear]                │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
└──────────────────────────────────────────────────┘
```

### Custom Models - Model Dropdown

The "Model" column in the Custom Models table is a dropdown (`Picker`), populated from APIBypass's `ConfigManager.mappings`. The data source is all `ModelMapping.incomingModel` values across all providers. When a user selects a model from the dropdown, the `CustomModelEntry.modelMappingId` is set to the corresponding `ModelMapping.id`.

## 4. Data Models

### CodexAdaptorConfig (APIBypass internal, UserDefaults)

```swift
struct CodexAdaptorConfig: Codable, Equatable {
    var port: Int = 15721
    var wireAPI: WireAPI = .chat
    var reasoningOverrideEnabled: Bool = false
    var reasoningConfig: ReasoningConfig?
    var customModels: [CustomModelEntry] = []
    var cdpSettings: CDPInjectionSettings = CDPInjectionSettings()
    
    enum WireAPI: String, Codable, CaseIterable {
        case chat = "chat"
        case responses = "responses"
    }
}

struct CustomModelEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var alias: String              // Display name in Codex model picker
    var modelMappingId: UUID       // References APIBypass ModelMapping
    var contextWindow: UInt64 = 128000
}
```

Stored at UserDefaults key `"com.apibypass.codexAdaptor"`.

### ~/.codex/ Files (Codex CLI compatibility)

Written by `CodexConfigService` (from CodexRouterCore):

- `~/.codex/config.toml` — Codex CLI reads this
- `~/.codex/providers.json` — proxy-internal metadata
- `~/.codex/<provider-id>-model-catalog.json` — model catalog for Codex's picker

## 5. Service Architecture

### CodexAdaptorService

```swift
@MainActor
final class CodexAdaptorService: ObservableObject {
    @Published var isRunning = false
    @Published var port: Int
    
    private var proxyServer: ProxyServer?
    private let codexConfigService: CodexConfigService
    
    func start(configManager: ConfigManager) async throws { ... }
    func stop() async { ... }
    func updateConfig(_ config: CodexAdaptorConfig, configManager: ConfigManager) async { ... }
}
```

### CodexConfigBridge

```swift
struct CodexConfigBridge {
    /// Extracts all incomingModel names from APIBypass's ConfigManager
    static func availableModels(from configManager: ConfigManager) -> [ModelMapping]
    
    /// Resolves a CustomModelEntry to the actual model name
    static func resolveModelName(entry: CustomModelEntry, configManager: ConfigManager) -> String?
    
    /// Generates CodexConfigService-compatible provider config from APIBypass state
    static func buildCodexProvider(config: CodexAdaptorConfig, configManager: ConfigManager) -> CodexModelProvider
}
```

### Request Flow

```
Codex CLI
  │ POST /v1/responses
  ▼
Codex Adaptor Server (:15721)
  │ RequestHandler (CodexRouterCore)
  │   Responses → Chat Completions conversion
  │   Reasoning parameter injection (ReasoningRectifier)
  │   Custom model → actual model mapping
  ▼
APIBypass Server (:8390)
  │ ProxyEngine
  │   Model mapping + parameter injection
  │   Format translation (if needed)
  ▼
Upstream Provider
```

**Note:** The Codex Adaptor's upstream base URL is automatically set to `http://127.0.0.1:{APIBypass port}`. This is not user-configurable — it always points to the running APIBypass server. The port is read from APIBypass's server port setting.

## 6. Localization

### New Keys (LocalizationManager.swift)

| Key | English | Chinese |
|-----|---------|---------|
| `codex_adaptor` | Codex Adaptor | Codex Adaptor |
| `codex_service` | Service | 服务 |
| `codex_start` | Start | 启动 |
| `codex_stop` | Stop | 停止 |
| `codex_port` | Port | 端口 |
| `codex_status_running` | Running | 运行中 |
| `codex_status_stopped` | Stopped | 已停止 |
| `codex_wire_api` | Communication Protocol | 通信协议 |
| `codex_wire_chat` | Chat Completions | Chat Completions |
| `codex_wire_responses` | Responses API | Responses API |
| `codex_reasoning` | Reasoning Configuration | 推理配置 |
| `codex_override_reasoning` | Override Reasoning Config | 覆盖推理配置 |
| `codex_auto_detect` | Auto Detect | 自动检测 |
| `codex_thinking_param` | Thinking Param | 思考参数 |
| `codex_effort_param` | Effort Param | Effort 参数 |
| `codex_effort_value` | Effort Value | Effort 值映射 |
| `codex_output_format` | Output Format | 输出格式 |
| `codex_custom_models` | Custom Models | 自定义模型 |
| `codex_model_alias` | Alias | 别名 |
| `codex_model_from_apibypass` | Model (from APIBypass) | 模型（来自 APIBypass） |
| `codex_context_window` | Context Window | 上下文窗口 |
| `codex_add_model` | Add Model | 添加模型 |
| `codex_enhancements` | Codex Enhancements | Codex 增强 |
| `codex_plugin_unlock` | Plugin Entry Unlock | 插件入口解锁 |
| `codex_marketplace_unlock` | Marketplace Unlock | 市场解锁 |
| `codex_force_install` | Force Plugin Install | 强制安装插件 |
| `codex_debug_port` | Debug Port | 调试端口 |
| `codex_logs` | Logs | 日志 |
| `codex_clear_logs` | Clear | 清除 |
| `codex_export_logs` | Export | 导出 |

### Help Page Update

Add Codex Adaptor section to HelpView.swift covering:
- Feature overview (Responses API proxy, reasoning config, CDP enhancements)
- Usage steps (configure → start service → point Codex CLI to proxy port)
- Communication protocol options
- Custom model configuration

## 7. Integration Checklist

- [ ] Copy CodexRouterCore source into APIBypass/CodexRouterCore/
- [ ] Update Package.swift (add TOMLKit dependency, CodexRouterCore target)
- [ ] Create CodexAdaptorService.swift
- [ ] Create CodexConfigBridge.swift
- [ ] Create CodexAdaptorView.swift
- [ ] Modify MenuBarView.swift (add Codex Adaptor menu item)
- [ ] Modify APIBypassApp.swift (add CodexAdaptorService state)
- [ ] Add localization keys to LocalizationManager.swift
- [ ] Update HelpView.swift
- [ ] Update RELEASE_NOTES.md
- [ ] Update README.md and README_CN.md
- [ ] Build and verify
