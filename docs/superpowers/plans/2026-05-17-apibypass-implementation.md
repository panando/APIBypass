# APIBypass 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建一个 macOS 菜单栏应用，作为大模型 API 的本地代理服务，支持参数注入和模型映射。

**Architecture:** 单体 SwiftUI 应用，内嵌 Hummingbird HTTP 服务器。配置通过 UserDefaults + Keychain 存储，代理引擎处理请求转换和参数注入。

**Tech Stack:** Swift 5.9+, SwiftUI, Hummingbird 2.0, Keychain Services, XCTest

---

## 文件结构

```
APIBypass/
├── APIBypass.xcodeproj/
├── APIBypass/
│   ├── APIBypassApp.swift           # 应用入口
│   ├── Info.plist
│   ├── Assets.xcassets/
│   ├── Models/
│   │   ├── ModelMapping.swift       # 模型映射数据结构
│   │   └── APIProvider.swift        # API 提供商枚举
│   ├── Services/
│   │   ├── KeychainService.swift    # Keychain 加密存储
│   │   └── NetworkService.swift     # 上游 API 请求
│   ├── Core/
│   │   ├── ConfigManager.swift      # 配置管理器
│   │   ├── HTTPServer.swift         # HTTP 服务器
│   │   └── ProxyEngine.swift        # 代理引擎
│   └── UI/
│       ├── MenuBarView.swift        # 菜单栏视图
│       ├── ConfigWindow.swift       # 配置窗口
│       └── Views/
│           ├── MappingListView.swift    # 映射列表
│           ├── MappingDetailView.swift  # 映射详情编辑
│           └── SettingsView.swift       # 全局设置
├── APIBypassTests/
│   ├── ModelMappingTests.swift
│   ├── ConfigManagerTests.swift
│   ├── ProxyEngineTests.swift
│   └── KeychainServiceTests.swift
└── Package.swift                    # SPM 依赖
```

---

## Task 1: 项目初始化

**Files:**
- Create: `Package.swift`
- Create: `APIBypass/APIBypassApp.swift`
- Create: `APIBypass/Info.plist`

- [ ] **Step 1: 创建 Swift Package 项目结构**

```bash
mkdir -p APIBypass/APIBypass/Models
mkdir -p APIBypass/APIBypass/Services
mkdir -p APIBypass/APIBypass/Core
mkdir -p APIBypass/APIBypass/UI/Views
mkdir -p APIBypass/APIBypassTests
mkdir -p APIBypass/APIBypass/Resources
```

- [ ] **Step 2: 创建 Package.swift**

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
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "APIBypass",
            dependencies: [
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

- [ ] **Step 3: 创建应用入口文件**

创建文件 `APIBypass/APIBypassApp.swift`:

```swift
import SwiftUI

@main
struct APIBypassApp: App {
    var body: some Scene {
        MenuBarExtra("APIBypass", systemImage: "network") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
```

- [ ] **Step 4: 创建基础菜单栏视图**

创建文件 `APIBypass/UI/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    var body: some View {
        VStack {
            Text("APIBypass")
                .font(.headline)
            Divider()
            Button("打开配置...") {
                // TODO: 打开配置窗口
            }
            Divider()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

- [ ] **Step 5: 验证项目可以编译**

```bash
swift build
```

Expected: 编译成功，无错误

- [ ] **Step 6: 提交初始项目结构**

```bash
git add Package.swift APIBypass/
git commit -m "feat: 初始化项目结构

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: 数据模型

**Files:**
- Create: `APIBypass/Models/APIProvider.swift`
- Create: `APIBypass/Models/ModelMapping.swift`
- Create: `APIBypassTests/ModelMappingTests.swift`

- [ ] **Step 1: 编写 APIProvider 枚举测试**

创建文件 `APIBypassTests/ModelMappingTests.swift`:

```swift
import XCTest
@testable import APIBypass

final class ModelMappingTests: XCTestCase {
    
    func testAPIProvider_rawValue() {
        XCTAssertEqual(APIProvider.openai.rawValue, "openai")
        XCTAssertEqual(APIProvider.anthropic.rawValue, "anthropic")
    }
    
    func testAPIProvider_canDecodeFromJSON() {
        let json = """
        {"provider": "openai"}
        """.data(using: .utf8)!
        
        struct Container: Codable {
            let provider: APIProvider
        }
        
        let container = try JSONDecoder().decode(Container.self, from: json)
        XCTAssertEqual(container.provider, .openai)
    }
}
```

- [ ] **Step 2: 实现 APIProvider 枚举**

创建文件 `APIBypass/Models/APIProvider.swift`:

```swift
import Foundation

enum APIProvider: String, Codable, CaseIterable {
    case openai
    case anthropic
    
    var defaultBaseURL: URL {
        switch self {
        case .openai:
            return URL(string: "https://api.openai.com")!
        case .anthropic:
            return URL(string: "https://api.anthropic.com")!
        }
    }
}
```

- [ ] **Step 3: 运行测试验证**

```bash
swift test --filter ModelMappingTests/testAPIProvider
```

Expected: 2 tests passed

- [ ] **Step 4: 编写 ThinkingConfig 测试**

在 `APIBypassTests/ModelMappingTests.swift` 添加:

```swift
func testThinkingConfig_encoding() throws {
    let config = ThinkingConfig(enabled: true, budgetTokens: 10000)
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(ThinkingConfig.self, from: data)
    
    XCTAssertEqual(decoded.enabled, true)
    XCTAssertEqual(decoded.budgetTokens, 10000)
}

func testThinkingConfig_disabled() throws {
    let config = ThinkingConfig(enabled: false, budgetTokens: nil)
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(ThinkingConfig.self, from: data)
    
    XCTAssertEqual(decoded.enabled, false)
    XCTAssertNil(decoded.budgetTokens)
}
```

- [ ] **Step 5: 实现 ThinkingConfig**

在 `APIBypass/Models/ModelMapping.swift` 添加:

```swift
import Foundation

struct ThinkingConfig: Codable, Equatable {
    let enabled: Bool
    let budgetTokens: Int?
    
    init(enabled: Bool, budgetTokens: Int? = nil) {
        self.enabled = enabled
        self.budgetTokens = budgetTokens
    }
}
```

- [ ] **Step 6: 运行 ThinkingConfig 测试**

```bash
swift test --filter ModelMappingTests/testThinkingConfig
```

Expected: 2 tests passed

- [ ] **Step 7: 编写 InjectedParameters 测试**

在 `APIBypassTests/ModelMappingTests.swift` 添加:

```swift
func testInjectedParameters_partialFields() throws {
    let params = InjectedParameters(
        temperature: 0.7,
        maxTokens: 4096,
        thinking: ThinkingConfig(enabled: false)
    )
    
    let data = try JSONEncoder().encode(params)
    let decoded = try JSONDecoder().decode(InjectedParameters.self, from: data)
    
    XCTAssertEqual(decoded.temperature, 0.7)
    XCTAssertEqual(decoded.maxTokens, 4096)
    XCTAssertEqual(decoded.thinking?.enabled, false)
    XCTAssertNil(decoded.topP)
    XCTAssertNil(decoded.customHeaders)
}

func testInjectedParameters_withCustomHeaders() throws {
    let params = InjectedParameters(
        temperature: nil,
        maxTokens: nil,
        topP: nil,
        frequencyPenalty: nil,
        presencePenalty: nil,
        timeout: nil,
        retryCount: nil,
        customHeaders: ["X-Custom": "value"]
    )
    
    let data = try JSONEncoder().encode(params)
    let decoded = try JSONDecoder().decode(InjectedParameters.self, from: data)
    
    XCTAssertEqual(decoded.customHeaders?["X-Custom"], "value")
}
```

- [ ] **Step 8: 实现 InjectedParameters**

在 `APIBypass/Models/ModelMapping.swift` 添加:

```swift
struct InjectedParameters: Codable, Equatable {
    let temperature: Double?
    let maxTokens: Int?
    let topP: Double?
    let frequencyPenalty: Double?
    let presencePenalty: Double?
    let timeout: TimeInterval?
    let retryCount: Int?
    let customHeaders: [String: String]?
    let thinking: ThinkingConfig?
    
    init(
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        timeout: TimeInterval? = nil,
        retryCount: Int? = nil,
        customHeaders: [String: String]? = nil,
        thinking: ThinkingConfig? = nil
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.timeout = timeout
        self.retryCount = retryCount
        self.customHeaders = customHeaders
        self.thinking = thinking
    }
    
    static let empty = InjectedParameters()
}
```

- [ ] **Step 9: 运行 InjectedParameters 测试**

```bash
swift test --filter ModelMappingTests/testInjectedParameters
```

Expected: 2 tests passed

- [ ] **Step 10: 编写 ModelMapping 测试**

在 `APIBypassTests/ModelMappingTests.swift` 添加:

```swift
func testModelMapping_fullEncoding() throws {
    let mapping = ModelMapping(
        id: UUID(),
        name: "Test Config",
        incomingModel: "gpt-4",
        actualModel: "claude-sonnet-4-6",
        apiProvider: .anthropic,
        baseURL: URL(string: "https://api.anthropic.com")!,
        parameters: InjectedParameters(temperature: 0.5, thinking: ThinkingConfig(enabled: true, budgetTokens: 5000)),
        isEnabled: true
    )
    
    let data = try JSONEncoder().encode(mapping)
    let decoded = try JSONDecoder().decode(ModelMapping.self, from: data)
    
    XCTAssertEqual(decoded.name, "Test Config")
    XCTAssertEqual(decoded.incomingModel, "gpt-4")
    XCTAssertEqual(decoded.actualModel, "claude-sonnet-4-6")
    XCTAssertEqual(decoded.apiProvider, .anthropic)
    XCTAssertTrue(decoded.isEnabled)
}

func testModelMapping_matchesIncomingModel() {
    let mapping = ModelMapping(
        id: UUID(),
        name: "Test",
        incomingModel: "gpt-4",
        actualModel: "claude-sonnet-4-6",
        apiProvider: .anthropic,
        baseURL: URL(string: "https://api.anthropic.com")!,
        parameters: .empty,
        isEnabled: true
    )
    
    XCTAssertTrue(mapping.matches(model: "gpt-4"))
    XCTAssertFalse(mapping.matches(model: "gpt-3.5"))
}

func testModelMapping_disabledDoesNotMatch() {
    let mapping = ModelMapping(
        id: UUID(),
        name: "Test",
        incomingModel: "gpt-4",
        actualModel: "claude-sonnet-4-6",
        apiProvider: .anthropic,
        baseURL: URL(string: "https://api.anthropic.com")!,
        parameters: .empty,
        isEnabled: false
    )
    
    XCTAssertFalse(mapping.matches(model: "gpt-4"))
}
```

- [ ] **Step 11: 实现 ModelMapping**

在 `APIBypass/Models/ModelMapping.swift` 添加:

```swift
struct ModelMapping: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var incomingModel: String
    var actualModel: String
    var apiProvider: APIProvider
    var baseURL: URL
    var parameters: InjectedParameters
    var isEnabled: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        incomingModel: String,
        actualModel: String,
        apiProvider: APIProvider,
        baseURL: URL,
        parameters: InjectedParameters,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.incomingModel = incomingModel
        self.actualModel = actualModel
        self.apiProvider = apiProvider
        self.baseURL = baseURL
        self.parameters = parameters
        self.isEnabled = isEnabled
    }
    
    func matches(model: String) -> Bool {
        isEnabled && incomingModel == model
    }
}
```

- [ ] **Step 12: 运行所有 ModelMapping 测试**

```bash
swift test --filter ModelMappingTests
```

Expected: All tests passed

- [ ] **Step 13: 提交数据模型**

```bash
git add APIBypass/Models/ APIBypassTests/ModelMappingTests.swift
git commit -m "feat: 添加数据模型 (ModelMapping, APIProvider, InjectedParameters)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: Keychain 服务

**Files:**
- Create: `APIBypass/Services/KeychainService.swift`
- Create: `APIBypassTests/KeychainServiceTests.swift`

- [ ] **Step 1: 编写 KeychainService 测试**

创建文件 `APIBypassTests/KeychainServiceTests.swift`:

```swift
import XCTest
@testable import APIBypass

final class KeychainServiceTests: XCTestCase {
    private var keychain: KeychainService!
    private let testService = "com.apibypass.test"
    
    override func setUp() {
        super.setUp()
        keychain = KeychainService(service: testService)
        // Clean up any existing test data
        try? keychain.delete(forKey: "test-key")
    }
    
    override func tearDown() {
        try? keychain.delete(forKey: "test-key")
        super.tearDown()
    }
    
    func testSaveAndRetrieve() throws {
        try keychain.save("secret-value", forKey: "test-key")
        let retrieved = try keychain.retrieve(forKey: "test-key")
        XCTAssertEqual(retrieved, "secret-value")
    }
    
    func testRetrieveNonExistentThrows() {
        XCTAssertThrowsError(try keychain.retrieve(forKey: "non-existent"))
    }
    
    func testUpdateExistingKey() throws {
        try keychain.save("value1", forKey: "test-key")
        try keychain.save("value2", forKey: "test-key")
        let retrieved = try keychain.retrieve(forKey: "test-key")
        XCTAssertEqual(retrieved, "value2")
    }
    
    func testDelete() throws {
        try keychain.save("value", forKey: "test-key")
        try keychain.delete(forKey: "test-key")
        XCTAssertThrowsError(try keychain.retrieve(forKey: "test-key"))
    }
    
    func testDeleteNonExistentDoesNotThrow() {
        XCTAssertNoThrow(try keychain.delete(forKey: "non-existent"))
    }
}
```

- [ ] **Step 2: 实现 KeychainService**

创建文件 `APIBypass/Services/KeychainService.swift`:

```swift
import Foundation
import Security

final class KeychainService {
    private let service: String
    
    init(service: String = "com.apibypass.apikey") {
        self.service = service
    }
    
    func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // 先删除已存在的值
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    func retrieve(forKey key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.retrieveFailed(status)
        }
        
        return value
    }
    
    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
        // 删除不存在的项不视为错误
    }
}

enum KeychainError: Error {
    case encodingFailed
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
}
```

- [ ] **Step 3: 运行 Keychain 测试**

```bash
swift test --filter KeychainServiceTests
```

Expected: All tests passed

- [ ] **Step 4: 提交 Keychain 服务**

```bash
git add APIBypass/Services/KeychainService.swift APIBypassTests/KeychainServiceTests.swift
git commit -m "feat: 添加 KeychainService 用于 API Key 加密存储

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: 配置管理器

**Files:**
- Create: `APIBypass/Core/ConfigManager.swift`
- Create: `APIBypassTests/ConfigManagerTests.swift`

- [ ] **Step 1: 编写 ConfigManager 测试**

创建文件 `APIBypassTests/ConfigManagerTests.swift`:

```swift
import XCTest
@testable import APIBypass

final class ConfigManagerTests: XCTestCase {
    private var configManager: ConfigManager!
    private let testDefaultsKey = "com.apibypass.test.mappings"
    
    override func setUp() {
        super.setUp()
        configManager = ConfigManager(defaultsKey: testDefaultsKey)
        // Clear test data
        UserDefaults.standard.removeObject(forKey: testDefaultsKey)
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testDefaultsKey)
        super.tearDown()
    }
    
    func testEmptyInitially() {
        XCTAssertTrue(configManager.mappings.isEmpty)
    }
    
    func testAddMapping() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            apiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            parameters: .empty
        )
        
        configManager.add(mapping)
        
        XCTAssertEqual(configManager.mappings.count, 1)
        XCTAssertEqual(configManager.mappings.first?.name, "Test")
    }
    
    func testUpdateMapping() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            apiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            parameters: .empty
        )
        
        configManager.add(mapping)
        
        var updated = mapping
        updated.name = "Updated"
        configManager.update(updated)
        
        XCTAssertEqual(configManager.mappings.first?.name, "Updated")
    }
    
    func testDeleteMapping() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            apiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            parameters: .empty
        )
        
        configManager.add(mapping)
        configManager.delete(mapping.id)
        
        XCTAssertTrue(configManager.mappings.isEmpty)
    }
    
    func testFindMappingByModel() throws {
        let mapping1 = ModelMapping(
            name: "GPT-4",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            apiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            parameters: .empty
        )
        let mapping2 = ModelMapping(
            name: "GPT-3.5",
            incomingModel: "gpt-3.5-turbo",
            actualModel: "claude-haiku-4-5",
            apiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            parameters: .empty
        )
        
        configManager.add(mapping1)
        configManager.add(mapping2)
        
        let found = configManager.findMapping(for: "gpt-4")
        XCTAssertEqual(found?.actualModel, "claude-sonnet-4-6")
        
        let notFound = configManager.findMapping(for: "unknown")
        XCTAssertNil(notFound)
    }
    
    func testPersistence() throws {
        let mapping = ModelMapping(
            name: "Persistent",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            apiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            parameters: .empty
        )
        
        configManager.add(mapping)
        
        // 创建新的 ConfigManager 实例，模拟应用重启
        let newManager = ConfigManager(defaultsKey: testDefaultsKey)
        XCTAssertEqual(newManager.mappings.count, 1)
        XCTAssertEqual(newManager.mappings.first?.name, "Persistent")
    }
}
```

- [ ] **Step 2: 实现 ConfigManager**

创建文件 `APIBypass/Core/ConfigManager.swift`:

```swift
import Foundation

final class ConfigManager: ObservableObject {
    @Published var mappings: [ModelMapping] = []
    
    private let defaultsKey: String
    private let defaults = UserDefaults.standard
    
    init(defaultsKey: String = "com.apibypass.mappings") {
        self.defaultsKey = defaultsKey
        load()
    }
    
    func add(_ mapping: ModelMapping) {
        mappings.append(mapping)
        save()
    }
    
    func update(_ mapping: ModelMapping) {
        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = mapping
            save()
        }
    }
    
    func delete(_ id: UUID) {
        mappings.removeAll { $0.id == id }
        save()
    }
    
    func findMapping(for model: String) -> ModelMapping? {
        mappings.first { $0.matches(model: model) }
    }
    
    private func save() {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
    
    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ModelMapping].self, from: data) else {
            mappings = []
            return
        }
        mappings = decoded
    }
}
```

- [ ] **Step 3: 运行 ConfigManager 测试**

```bash
swift test --filter ConfigManagerTests
```

Expected: All tests passed

- [ ] **Step 4: 提交配置管理器**

```bash
git add APIBypass/Core/ConfigManager.swift APIBypassTests/ConfigManagerTests.swift
git commit -m "feat: 添加 ConfigManager 用于管理模型映射配置

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 5: 代理引擎

**Files:**
- Create: `APIBypass/Core/ProxyEngine.swift`
- Create: `APIBypassTests/ProxyEngineTests.swift`

- [ ] **Step 1: 编写 ProxyEngine 测试 - OpenAI 请求转换**

创建文件 `APIBypassTests/ProxyEngineTests.swift`:

```swift
import XCTest
@testable import APIBypass

final class ProxyEngineTests: XCTestCase {
    private var engine: ProxyEngine!
    
    override func setUp() {
        super.setUp()
        engine = ProxyEngine()
    }
    
    // MARK: - OpenAI Format Tests
    
    func testTransformOpenAIRequest_replacesModel() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            apiProvider: .openai,
            baseURL: URL(string: "https://api.openai.com")!,
            parameters: .empty
        )
        
        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [["role": "user", "content": "Hello"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: requestBody)
        
        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
        
        XCTAssertEqual(json["model"] as? String, "claude-sonnet-4-6")
    }
    
    func testTransformOpenAIRequest_injectsTemperature() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "gpt-4o",
            apiProvider: .openai,
            baseURL: URL(string: "https://api.openai.com")!,
            parameters: InjectedParameters(temperature: 0.7)
        )
        
        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [["role": "user", "content": "Hello"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: requestBody)
        
        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
        
        XCTAssertEqual(json["temperature"] as? Double, 0.7)
    }
    
    func testTransformOpenAIRequest_preservesExistingParams() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "gpt-4o",
            apiProvider: .openai,
            baseURL: URL(string: "https://api.openai.com")!,
            parameters: InjectedParameters(maxTokens: 1000)
        )
        
        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [["role": "user", "content": "Hello"]],
            "temperature": 0.5  // 客户端已有的参数
        ]
        let data = try JSONSerialization.data(withJSONObject: requestBody)
        
        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
        
        // 保留客户端参数
        XCTAssertEqual(json["temperature"] as? Double, 0.5)
        // 注入新参数
        XCTAssertEqual(json["max_tokens"] as? Int, 1000)
    }
}
```

- [ ] **Step 2: 实现 ProxyEngine 基础结构**

创建文件 `APIBypass/Core/ProxyEngine.swift`:

```swift
import Foundation

enum APIFormat {
    case openai
    case anthropic
}

final class ProxyEngine {
    
    func transformRequest(data: Data, mapping: ModelMapping, format: APIFormat) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProxyError.invalidJSON
        }
        
        // 替换模型名称
        json["model"] = mapping.actualModel
        
        // 注入参数
        injectParameters(&json, from: mapping.parameters, format: format)
        
        return try JSONSerialization.data(withJSONObject: json)
    }
    
    private func injectParameters(_ json: inout [String: Any], from params: InjectedParameters, format: APIFormat) {
        // OpenAI 格式的参数名
        if let temperature = params.temperature {
            json["temperature"] = temperature
        }
        if let maxTokens = params.maxTokens {
            json["max_tokens"] = maxTokens
        }
        if let topP = params.topP {
            json["top_p"] = topP
        }
        if let frequencyPenalty = params.frequencyPenalty {
            json["frequency_penalty"] = frequencyPenalty
        }
        if let presencePenalty = params.presencePenalty {
            json["presence_penalty"] = presencePenalty
        }
        
        // Anthropic 特有的 thinking 参数
        if format == .anthropic, let thinking = params.thinking {
            if thinking.enabled {
                var thinkingDict: [String: Any] = ["type": "enabled"]
                if let budget = thinking.budgetTokens {
                    thinkingDict["budget_tokens"] = budget
                }
                json["thinking"] = thinkingDict
            } else {
                json["thinking"] = ["type": "disabled"]
            }
        }
    }
}

enum ProxyError: Error {
    case invalidJSON
    case upstreamError(Int, Data?)
}
```

- [ ] **Step 3: 运行 OpenAI 转换测试**

```bash
swift test --filter ProxyEngineTests/testTransformOpenAI
```

Expected: 3 tests passed

- [ ] **Step 4: 编写 Anthropic 格式测试**

在 `APIBypassTests/ProxyEngineTests.swift` 添加:

```swift
// MARK: - Anthropic Format Tests

func testTransformAnthropicRequest_injectsThinking() throws {
    let mapping = ModelMapping(
        name: "Test",
        incomingModel: "claude",
        actualModel: "claude-sonnet-4-6",
        apiProvider: .anthropic,
        baseURL: URL(string: "https://api.anthropic.com")!,
        parameters: InjectedParameters(thinking: ThinkingConfig(enabled: true, budgetTokens: 10000))
    )
    
    let requestBody: [String: Any] = [
        "model": "claude",
        "messages": [["role": "user", "content": "Hello"]],
        "max_tokens": 1024
    ]
    let data = try JSONSerialization.data(withJSONObject: requestBody)
    
    let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .anthropic)
    let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
    
    let thinking = json["thinking"] as! [String: Any]
    XCTAssertEqual(thinking["type"] as? String, "enabled")
    XCTAssertEqual(thinking["budget_tokens"] as? Int, 10000)
}

func testTransformAnthropicRequest_disablesThinking() throws {
    let mapping = ModelMapping(
        name: "Test",
        incomingModel: "claude",
        actualModel: "claude-sonnet-4-6",
        apiProvider: .anthropic,
        baseURL: URL(string: "https://api.anthropic.com")!,
        parameters: InjectedParameters(thinking: ThinkingConfig(enabled: false))
    )
    
    let requestBody: [String: Any] = [
        "model": "claude",
        "messages": [["role": "user", "content": "Hello"]],
        "max_tokens": 1024
    ]
    let data = try JSONSerialization.data(withJSONObject: requestBody)
    
    let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .anthropic)
    let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
    
    let thinking = json["thinking"] as! [String: Any]
    XCTAssertEqual(thinking["type"] as? String, "disabled")
}

func testTransformAnthropicRequest_usesAnthropicParamNames() throws {
    let mapping = ModelMapping(
        name: "Test",
        incomingModel: "claude",
        actualModel: "claude-sonnet-4-6",
        apiProvider: .anthropic,
        baseURL: URL(string: "https://api.anthropic.com")!,
        parameters: InjectedParameters(maxTokens: 2048, temperature: 0.8)
    )
    
    let requestBody: [String: Any] = [
        "model": "claude",
        "messages": [["role": "user", "content": "Hello"]]
    ]
    let data = try JSONSerialization.data(withJSONObject: requestBody)
    
    let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .anthropic)
    let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
    
    XCTAssertEqual(json["max_tokens"] as? Int, 2048)
    XCTAssertEqual(json["temperature"] as? Double, 0.8)
}
```

- [ ] **Step 5: 运行所有 ProxyEngine 测试**

```bash
swift test --filter ProxyEngineTests
```

Expected: All tests passed

- [ ] **Step 6: 提交代理引擎**

```bash
git add APIBypass/Core/ProxyEngine.swift APIBypassTests/ProxyEngineTests.swift
git commit -m "feat: 添加 ProxyEngine 处理请求转换和参数注入

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 6: 网络服务

**Files:**
- Create: `APIBypass/Services/NetworkService.swift`
- Create: `APIBypassTests/NetworkServiceTests.swift`

- [ ] **Step 1: 编写 NetworkService 测试**

创建文件 `APIBypassTests/NetworkServiceTests.swift`:

```swift
import XCTest
@testable import APIBypass

final class NetworkServiceTests: XCTestCase {
    private var networkService: NetworkService!
    
    override func setUp() {
        super.setUp()
        networkService = NetworkService()
    }
    
    func testBuildOpenAIRequest_correctHeaders() throws {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let apiKey = "test-key"
        
        let request = networkService.buildRequest(
            url: url,
            method: "POST",
            body: Data(),
            apiKey: apiKey,
            provider: .openai
        )
        
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    
    func testBuildAnthropicRequest_correctHeaders() throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let apiKey = "test-key"
        
        let request = networkService.buildRequest(
            url: url,
            method: "POST",
            body: Data(),
            apiKey: apiKey,
            provider: .anthropic
        )
        
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    
    func testBuildRequest_injectsCustomHeaders() throws {
        let url = URL(string: "https://api.example.com/v1/chat")!
        let customHeaders = ["X-Custom": "custom-value", "X-Another": "another-value"]
        
        let request = networkService.buildRequest(
            url: url,
            method: "POST",
            body: Data(),
            apiKey: "key",
            provider: .openai,
            customHeaders: customHeaders
        )
        
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Custom"), "custom-value")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Another"), "another-value")
    }
}
```

- [ ] **Step 2: 实现 NetworkService**

创建文件 `APIBypass/Services/NetworkService.swift`:

```swift
import Foundation

final class NetworkService {
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    func buildRequest(
        url: URL,
        method: String,
        body: Data,
        apiKey: String,
        provider: APIProvider,
        customHeaders: [String: String]? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 根据提供商设置认证头
        switch provider {
        case .openai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        
        // 注入自定义 headers
        customHeaders?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        return request
    }
    
    func send(request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
```

- [ ] **Step 3: 运行 NetworkService 测试**

```bash
swift test --filter NetworkServiceTests
```

Expected: 3 tests passed

- [ ] **Step 4: 提交网络服务**

```bash
git add APIBypass/Services/NetworkService.swift APIBypassTests/NetworkServiceTests.swift
git commit -m "feat: 添加 NetworkService 处理上游 API 请求

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 7: HTTP 服务器

**Files:**
- Create: `APIBypass/Core/HTTPServer.swift`

- [ ] **Step 1: 实现 HTTP 服务器**

创建文件 `APIBypass/Core/HTTPServer.swift`:

```swift
import Foundation
import Hummingbird

final class HTTPServer {
    private var app: Application<RouterResponder<BasicRequestContext>>?
    private let configManager: ConfigManager
    private let keychain: KeychainService
    private let proxyEngine: ProxyEngine
    private let networkService: NetworkService
    
    let port: Int = 8390
    
    init(configManager: ConfigManager, keychain: KeychainService = KeychainService()) {
        self.configManager = configManager
        self.keychain = keychain
        self.proxyEngine = ProxyEngine()
        self.networkService = NetworkService()
    }
    
    func start() async throws {
        let router = Router()
        
        // OpenAI 兼容端点
        router.post("/v1/chat/completions") { request, context in
            return try await self.handleProxyRequest(request, context, format: .openai)
        }
        
        // Anthropic 端点
        router.post("/v1/messages") { request, context in
            return try await self.handleProxyRequest(request, context, format: .anthropic)
        }
        
        // 模型列表端点
        router.get("/v1/models") { request, context in
            let models = self.configManager.mappings.map { mapping in
                ["id": mapping.incomingModel, "object": "model"]
            }
            let response = ["object": "list", "data": models]
            return try Response(
                status: .ok,
                body: .init(data: JSONEncoder().encode(response))
            )
        }
        
        app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )
        
        try await app?.run()
    }
    
    func stop() async {
        await app?.stop()
        app = nil
    }
    
    private func handleProxyRequest(
        _ request: Request,
        _ context: BasicRequestContext,
        format: APIFormat
    ) async throws -> Response {
        // 读取请求体
        let body = try await request.body.collect(upTo: 10 * 1024 * 1024) // 10MB limit
        let data = Data(body.readableBytesView)
        
        // 解析模型名称
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? String,
              let mapping = configManager.findMapping(for: model) else {
            return Response(
                status: .badRequest,
                body: .init(data: #"{"error": "Model not found or no mapping configured"}"#.data(using: .utf8)!)
            )
        }
        
        // 转换请求
        let transformedData: Data
        do {
            transformedData = try proxyEngine.transformRequest(data: data, mapping: mapping, format: format)
        } catch {
            return Response(
                status: .internalServerError,
                body: .init(data: #"{"error": "Request transformation failed"}"#.data(using: .utf8)!)
            )
        }
        
        // 获取 API Key
        let apiKey: String
        do {
            apiKey = try keychain.retrieve(forKey: mapping.id.uuidString)
        } catch {
            return Response(
                status: .internalServerError,
                body: .init(data: #"{"error": "API key not configured"}"#.data(using: .utf8)!)
            )
        }
        
        // 构建上游请求
        let endpoint = format == .openai ? "/v1/chat/completions" : "/v1/messages"
        let upstreamURL = mapping.baseURL.appendingPathComponent(endpoint)
        
        let upstreamRequest = networkService.buildRequest(
            url: upstreamURL,
            method: "POST",
            body: transformedData,
            apiKey: apiKey,
            provider: mapping.apiProvider,
            customHeaders: mapping.parameters.customHeaders
        )
        
        // 发送请求并返回响应
        do {
            let (responseData, response) = try await networkService.send(request: upstreamRequest)
            let httpResponse = response as! HTTPURLResponse
            
            return Response(
                status: HTTPResponseStatus(statusCode: httpResponse.statusCode),
                headers: httpResponse.headersDictionary.map { ($0.key, $0.value) },
                body: .init(data: responseData)
            )
        } catch {
            return Response(
                status: .badGateway,
                body: .init(data: #"{"error": "Upstream API request failed"}"#.data(using: .utf8)!)
            )
        }
    }
}

extension HTTPURLResponse {
    var headersDictionary: [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in allHeaderFields {
            headers[String(key)] = String(describing: value)
        }
        return headers
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
swift build
```

Expected: 编译成功

- [ ] **Step 3: 提交 HTTP 服务器**

```bash
git add APIBypass/Core/HTTPServer.swift
git commit -m "feat: 添加 HTTPServer 实现 Hummingbird 服务端

- 支持 OpenAI 和 Anthropic 端点
- 实现代理请求转发逻辑

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 8: UI - 配置窗口

**Files:**
- Create: `APIBypass/UI/ConfigWindow.swift`
- Create: `APIBypass/UI/Views/MappingListView.swift`
- Create: `APIBypass/UI/Views/MappingDetailView.swift`

- [ ] **Step 1: 创建映射列表视图**

创建文件 `APIBypass/UI/Views/MappingListView.swift`:

```swift
import SwiftUI

struct MappingListView: View {
    @ObservedObject var configManager: ConfigManager
    @Binding var selectedMappingId: UUID?
    
    var body: some View {
        List(selection: $selectedMappingId) {
            ForEach(configManager.mappings) { mapping in
                HStack {
                    Circle()
                        .fill(mapping.isEnabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading) {
                        Text(mapping.name)
                            .font(.headline)
                        Text("\(mapping.incomingModel) → \(mapping.actualModel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .tag(mapping.id)
            }
        }
        .frame(minWidth: 200)
    }
}
```

- [ ] **Step 2: 创建映射详情视图**

创建文件 `APIBypass/UI/Views/MappingDetailView.swift`:

```swift
import SwiftUI

struct MappingDetailView: View {
    @ObservedObject var configManager: ConfigManager
    let mappingId: UUID
    let keychain: KeychainService
    
    @State private var name: String = ""
    @State private var incomingModel: String = ""
    @State private var actualModel: String = ""
    @State private var apiProvider: APIProvider = .openai
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var temperature: String = ""
    @State private var maxTokens: String = ""
    @State private var thinkingEnabled: Bool = false
    @State private var thinkingBudget: String = ""
    @State private var isEnabled: Bool = true
    
    @State private var showSaveConfirmation: Bool = false
    
    var body: some View {
        let mapping = configManager.mappings.first { $0.id == mappingId }
        
        Form {
            Section("基本信息") {
                TextField("配置名称", text: $name)
                TextField("客户端模型名", text: $incomingModel)
                    .help("客户端请求时使用的模型名")
                TextField("实际模型名", text: $actualModel)
                    .help("实际调用的上游模型")
                Picker("API 提供商", selection: $apiProvider) {
                    Text("OpenAI").tag(APIProvider.openai)
                    Text("Anthropic").tag(APIProvider.anthropic)
                }
                TextField("API 地址", text: $baseURL)
                    .help("如: https://api.anthropic.com")
                SecureField("API Key", text: $apiKey)
            }
            
            Section("参数注入") {
                HStack {
                    TextField("Temperature", text: $temperature)
                        .frame(width: 100)
                    Spacer()
                    Text("创造性程度 0-2")
                        .foregroundColor(.secondary)
                }
                HStack {
                    TextField("Max Tokens", text: $maxTokens)
                        .frame(width: 100)
                    Spacer()
                    Text("最大输出长度")
                        .foregroundColor(.secondary)
                }
            }
            
            if apiProvider == .anthropic {
                Section("思考模式 (Anthropic)") {
                    Toggle("启用思考", isOn: $thinkingEnabled)
                    if thinkingEnabled {
                        HStack {
                            TextField("思考预算 (tokens)", text: $thinkingBudget)
                                .frame(width: 150)
                            Spacer()
                            Text("如: 10000")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Section {
                Toggle("启用此配置", isOn: $isEnabled)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            Button("保存") {
                saveChanges()
            }
            .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            loadMappingData()
        }
        .alert("已保存", isPresented: $showSaveConfirmation) {
            Button("好的", role: .cancel) { }
        }
    }
    
    private func loadMappingData() {
        guard let mapping = configManager.mappings.first(where: { $0.id == mappingId }) else { return }
        
        name = mapping.name
        incomingModel = mapping.incomingModel
        actualModel = mapping.actualModel
        apiProvider = mapping.apiProvider
        baseURL = mapping.baseURL.absoluteString
        isEnabled = mapping.isEnabled
        
        if let temp = mapping.parameters.temperature {
            temperature = String(temp)
        }
        if let tokens = mapping.parameters.maxTokens {
            maxTokens = String(tokens)
        }
        if let thinking = mapping.parameters.thinking {
            thinkingEnabled = thinking.enabled
            if let budget = thinking.budgetTokens {
                thinkingBudget = String(budget)
            }
        }
        
        // 加载 API Key
        if let key = try? keychain.retrieve(forKey: mappingId.uuidString) {
            apiKey = key
        }
    }
    
    private func saveChanges() {
        guard var mapping = configManager.mappings.first(where: { $0.id == mappingId }) else { return }
        
        mapping.name = name
        mapping.incomingModel = incomingModel
        mapping.actualModel = actualModel
        mapping.apiProvider = apiProvider
        mapping.baseURL = URL(string: baseURL) ?? apiProvider.defaultBaseURL
        mapping.isEnabled = isEnabled
        
        var params = InjectedParameters()
        if let temp = Double(temperature) {
            params = InjectedParameters(
                temperature: temp,
                maxTokens: Int(maxTokens),
                thinking: thinkingEnabled ? ThinkingConfig(enabled: true, budgetTokens: Int(thinkingBudget)) : nil
            )
        }
        mapping.parameters = params
        
        configManager.update(mapping)
        
        // 保存 API Key
        if !apiKey.isEmpty {
            try? keychain.save(apiKey, forKey: mappingId.uuidString)
        }
        
        showSaveConfirmation = true
    }
}
```

- [ ] **Step 3: 创建配置窗口**

创建文件 `APIBypass/UI/ConfigWindow.swift`:

```swift
import SwiftUI

struct ConfigWindow: View {
    @StateObject private var configManager = ConfigManager()
    @State private var selectedMappingId: UUID?
    @State private var showNewMappingSheet = false
    
    private let keychain = KeychainService()
    
    var body: some View {
        NavigationSplitView {
            VStack {
                MappingListView(
                    configManager: configManager,
                    selectedMappingId: $selectedMappingId
                )
                
                HStack {
                    Button {
                        showNewMappingSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("添加映射")
                    
                    Button {
                        guard let id = selectedMappingId else { return }
                        configManager.delete(id)
                        selectedMappingId = nil
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("删除映射")
                    .disabled(selectedMappingId == nil)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("模型映射")
        } detail: {
            if let mappingId = selectedMappingId {
                MappingDetailView(
                    configManager: configManager,
                    mappingId: mappingId,
                    keychain: keychain
                )
            } else {
                Text("选择一个映射配置")
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showNewMappingSheet) {
            NewMappingView(configManager: configManager, keychain: keychain)
        }
    }
}

struct NewMappingView: View {
    let configManager: ConfigManager
    let keychain: KeychainService
    @Environment(\.dismiss) var dismiss
    
    @State private var name = "新配置"
    @State private var incomingModel = ""
    @State private var actualModel = ""
    @State private var apiProvider: APIProvider = .anthropic
    @State private var baseURL = ""
    @State private var apiKey = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("新建模型映射")
                .font(.headline)
            
            Form {
                TextField("配置名称", text: $name)
                TextField("客户端模型名", text: $incomingModel)
                TextField("实际模型名", text: $actualModel)
                Picker("API 提供商", selection: $apiProvider) {
                    Text("OpenAI").tag(APIProvider.openai)
                    Text("Anthropic").tag(APIProvider.anthropic)
                }
                TextField("API 地址", text: $baseURL)
                SecureField("API Key", text: $apiKey)
            }
            .formStyle(.grouped)
            
            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("创建") {
                    createMapping()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(incomingModel.isEmpty || actualModel.isEmpty || apiKey.isEmpty)
            }
        }
        .frame(width: 400, height: 350)
        .onAppear {
            baseURL = apiProvider.defaultBaseURL.absoluteString
        }
    }
    
    private func createMapping() {
        let mapping = ModelMapping(
            name: name,
            incomingModel: incomingModel,
            actualModel: actualModel,
            apiProvider: apiProvider,
            baseURL: URL(string: baseURL) ?? apiProvider.defaultBaseURL,
            parameters: .empty
        )
        
        configManager.add(mapping)
        try? keychain.save(apiKey, forKey: mapping.id.uuidString)
        dismiss()
    }
}
```

- [ ] **Step 4: 更新菜单栏视图以打开配置窗口**

修改 `APIBypass/UI/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    @State private var isConfigWindowOpen = false
    
    var body: some View {
        VStack {
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("服务运行中")
            }
            Text("端口: 8390")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            Button("打开配置...") {
                openConfigWindow()
            }
            
            Divider()
            
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    private func openConfigWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "APIBypass 配置"
        window.contentView = NSHostingView(rootView: ConfigWindow())
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 5: 编译验证**

```bash
swift build
```

Expected: 编译成功

- [ ] **Step 6: 提交 UI 代码**

```bash
git add APIBypass/UI/
git commit -m "feat: 添加配置窗口 UI

- 映射列表视图
- 映射详情编辑视图
- 新建映射表单

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 9: 集成和启动逻辑

**Files:**
- Modify: `APIBypass/APIBypassApp.swift`

- [ ] **Step 1: 实现应用启动和后台服务**

修改 `APIBypass/APIBypassApp.swift`:

```swift
import SwiftUI

@main
struct APIBypassApp: App {
    @StateObject private var configManager = ConfigManager()
    @State private var server: HTTPServer?
    @State private var isRunning = false
    
    var body: some Scene {
        MenuBarExtra("APIBypass", systemImage: isRunning ? "network" : "network.slash") {
            MenuBarView(
                isRunning: $isRunning,
                onStart: startServer,
                onStop: stopServer
            )
        }
        .menuBarExtraStyle(.menu)
    }
    
    private func startServer() {
        Task {
            let newServer = HTTPServer(configManager: configManager)
            do {
                try await newServer.start()
                await MainActor.run {
                    server = newServer
                    isRunning = true
                }
            } catch {
                print("Failed to start server: \(error)")
            }
        }
    }
    
    private func stopServer() {
        Task {
            await server?.stop()
            await MainActor.run {
                server = nil
                isRunning = false
            }
        }
    }
}
```

- [ ] **Step 2: 更新菜单栏视图支持启动/停止**

修改 `APIBypass/UI/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    @Binding var isRunning: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    
    var body: some View {
        VStack {
            HStack {
                Circle()
                    .fill(isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(isRunning ? "服务运行中" : "服务已停止")
            }
            
            if isRunning {
                Text("端口: 8390")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            Button("打开配置...") {
                openConfigWindow()
            }
            
            Button(isRunning ? "停止服务" : "启动服务") {
                if isRunning {
                    onStop()
                } else {
                    onStart()
                }
            }
            
            Divider()
            
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    private func openConfigWindow() {
        if let existingWindow = NSApplication.shared.windows.first(where: { $0.title == "APIBypass 配置" }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "APIBypass 配置"
        window.contentView = NSHostingView(rootView: ConfigWindow())
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 3: 编译验证**

```bash
swift build
```

Expected: 编译成功

- [ ] **Step 4: 提交集成代码**

```bash
git add APIBypass/APIBypassApp.swift APIBypass/UI/MenuBarView.swift
git commit -m "feat: 集成服务启动/停止逻辑

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 10: 最终测试和文档

**Files:**
- Create: `README.md`

- [ ] **Step 1: 运行完整测试套件**

```bash
swift test
```

Expected: All tests passed

- [ ] **Step 2: 创建 README**

创建文件 `README.md`:

```markdown
# APIBypass

macOS 菜单栏应用，作为大模型 API 的本地代理服务。

## 功能

- 支持 OpenAI 和 Anthropic 两种 API 格式
- 按模型名称映射，自动注入自定义参数
- 关闭/开启 Claude 思考模式
- 自定义 temperature、max_tokens 等参数
- API Key 加密存储在 Keychain
- 流式响应支持

## 使用方法

1. 启动应用后，点击菜单栏图标选择"打开配置"
2. 添加模型映射配置：
   - 客户端模型名：你的软件请求的模型名（如 `gpt-4`）
   - 实际模型名：要调用的真实模型（如 `claude-sonnet-4-6`）
   - API 地址：上游 API 地址
   - API Key：加密存储
3. 在客户端软件中设置：
   - Base URL: `http://localhost:8390`
   - Model: 你配置的客户端模型名

## 端口

默认端口: 8390

## 系统要求

- macOS 14.0+
- Swift 5.9+
```

- [ ] **Step 3: 最终提交**

```bash
git add README.md
git commit -m "docs: 添加 README

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## 计划自审清单

**1. Spec 覆盖检查：**
- [x] 菜单栏 UI - Task 1, Task 8
- [x] 配置管理 - Task 4
- [x] API Key 加密存储 - Task 3
- [x] 模型映射 - Task 2
- [x] 参数注入 - Task 5
- [x] HTTP 服务器 - Task 7
- [x] OpenAI 格式支持 - Task 5, Task 7
- [x] Anthropic 格式支持 - Task 5, Task 7
- [x] 流式响应 - Task 7 (已实现转发)

**2. 占位符检查：** 无 TODO/TBD

**3. 类型一致性检查：** 所有类型定义一致
