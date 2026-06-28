import XCTest
@testable import APIBypass

final class CodexAdaptorConfigTests: XCTestCase {

    // MARK: - Test 1.1: 新字段存在且独立存储

    func test_chatCustomModels_storesIndependently() {
        var config = CodexAdaptorConfig()

        let chatEntry = CustomModelEntry(alias: "chat-model", modelMappingId: UUID(), contextWindow: 128000)
        config.chatCustomModels = [chatEntry]

        XCTAssertEqual(config.chatCustomModels.count, 1)
        XCTAssertEqual(config.responsesCustomModels.count, 0)
    }

    func test_responsesCustomModels_storesIndependently() {
        var config = CodexAdaptorConfig()

        let responsesEntry = CustomModelEntry(alias: "resp-model", modelMappingId: UUID(), contextWindow: 200000)
        config.responsesCustomModels = [responsesEntry]

        XCTAssertEqual(config.responsesCustomModels.count, 1)
        XCTAssertEqual(config.chatCustomModels.count, 0)
    }

    // MARK: - Test 1.2: currentCustomModels 根据 wireAPI 返回正确的列表

    func test_currentCustomModels_returnsChatModels_whenWireAPIIsChat() {
        var config = CodexAdaptorConfig()
        config.wireAPI = .chat

        let chatEntry = CustomModelEntry(alias: "chat-model", modelMappingId: UUID(), contextWindow: 128000)
        config.chatCustomModels = [chatEntry]

        XCTAssertEqual(config.currentCustomModels.count, 1)
        XCTAssertEqual(config.currentCustomModels.first?.alias, "chat-model")
    }

    func test_currentCustomModels_returnsResponsesModels_whenWireAPIIsResponses() {
        var config = CodexAdaptorConfig()
        config.wireAPI = .responses

        let responsesEntry = CustomModelEntry(alias: "resp-model", modelMappingId: UUID(), contextWindow: 200000)
        config.responsesCustomModels = [responsesEntry]

        XCTAssertEqual(config.currentCustomModels.count, 1)
        XCTAssertEqual(config.currentCustomModels.first?.alias, "resp-model")
    }

    func test_currentCustomModels_setter_updatesCorrectList() {
        var config = CodexAdaptorConfig()
        config.wireAPI = .chat

        let newEntry = CustomModelEntry(alias: "new-model", modelMappingId: UUID(), contextWindow: 100000)
        config.currentCustomModels = [newEntry]

        XCTAssertEqual(config.chatCustomModels.count, 1)
        XCTAssertEqual(config.responsesCustomModels.count, 0)

        config.wireAPI = .responses
        let anotherEntry = CustomModelEntry(alias: "another-model", modelMappingId: UUID(), contextWindow: 200000)
        config.currentCustomModels = [anotherEntry]

        XCTAssertEqual(config.chatCustomModels.count, 1)  // 之前设置的保留
        XCTAssertEqual(config.responsesCustomModels.count, 1)
    }

    // MARK: - Test 1.3: 数据迁移

    func test_migration_fromLegacyCustomModels_toChatCustomModels() {
        var config = CodexAdaptorConfig()

        // 模拟旧格式数据
        let legacyEntry = CustomModelEntry(alias: "legacy-model", modelMappingId: UUID(), contextWindow: 128000)
        config.customModels = [legacyEntry]  // 旧字段

        // 执行迁移
        config.migrateFromLegacy()

        // 验证迁移结果
        XCTAssertEqual(config.chatCustomModels.count, 1)
        XCTAssertEqual(config.chatCustomModels.first?.alias, "legacy-model")
    }

    func test_migration_doesNotOverwrite_existingData() {
        var config = CodexAdaptorConfig()

        // 已有新格式数据
        let existingEntry = CustomModelEntry(alias: "existing-model", modelMappingId: UUID(), contextWindow: 128000)
        config.chatCustomModels = [existingEntry]

        // 旧字段也有数据
        let legacyEntry = CustomModelEntry(alias: "legacy-model", modelMappingId: UUID(), contextWindow: 128000)
        config.customModels = [legacyEntry]

        // 执行迁移
        config.migrateFromLegacy()

        // 已有数据不被覆盖
        XCTAssertEqual(config.chatCustomModels.count, 1)
        XCTAssertEqual(config.chatCustomModels.first?.alias, "existing-model")
    }

    // MARK: - Test 1.4: Codable 编解码

    func test_codexAdaptorConfig_encodesBothModelLists() throws {
        var config = CodexAdaptorConfig()
        config.wireAPI = .chat

        let chatEntry = CustomModelEntry(alias: "chat-model", modelMappingId: UUID(), contextWindow: 128000)
        let responsesEntry = CustomModelEntry(alias: "resp-model", modelMappingId: UUID(), contextWindow: 200000)
        config.chatCustomModels = [chatEntry]
        config.responsesCustomModels = [responsesEntry]

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CodexAdaptorConfig.self, from: data)

        XCTAssertEqual(decoded.chatCustomModels.count, 1)
        XCTAssertEqual(decoded.responsesCustomModels.count, 1)
        XCTAssertEqual(decoded.wireAPI, .chat)
    }

    // MARK: - Test 1.6: save 同步 upstreamWireAPI 到 providers.json

    func test_save_syncsUpstreamWireAPIToProvidersJSON() async throws {
        // 保存配置，wireAPI = .responses
        var config = CodexAdaptorConfig()
        config.wireAPI = .responses
        config.port = 15721

        await CodexAdaptorConfigStore.shared.save(config)

        // 读取 providers.json 验证 upstreamWireAPI 被同步
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let providersPath = home + "/.codex/providers.json"

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: providersPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = json["providers"] as? [String: Any],
              let apibypass = providers["apibypass"] as? [String: Any],
              let upstreamWireAPI = apibypass["upstreamWireAPI"] as? String else {
            XCTFail("Failed to read providers.json")
            return
        }

        XCTAssertEqual(upstreamWireAPI, "responses", "save() should sync upstreamWireAPI to providers.json")
    }

    // MARK: - Test 1.7: 切换协议时 providers.json 正确更新

    func test_save_updatesProvidersJSON_whenSwitchingProtocol() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let providersPath = home + "/.codex/providers.json"

        // 先保存为 chat
        var config = CodexAdaptorConfig()
        config.wireAPI = .chat
        await CodexAdaptorConfigStore.shared.save(config)

        // 验证 providers.json 是 "chat"
        var data = try Data(contentsOf: URL(fileURLWithPath: providersPath))
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var providers = json["providers"] as? [String: Any] ?? [:]
        var apibypass = providers["apibypass"] as? [String: Any] ?? [:]
        XCTAssertEqual(apibypass["upstreamWireAPI"] as? String, "chat")

        // 切换到 responses
        config.wireAPI = .responses
        await CodexAdaptorConfigStore.shared.save(config)

        // 验证 providers.json 更新为 "responses"
        data = try Data(contentsOf: URL(fileURLWithPath: providersPath))
        json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        providers = json["providers"] as? [String: Any] ?? [:]
        apibypass = providers["apibypass"] as? [String: Any] ?? [:]
        XCTAssertEqual(apibypass["upstreamWireAPI"] as? String, "responses", "Switching protocol should update providers.json")
    }

    // MARK: - Test 2.1: 镜像文件存储在正确位置

    func test_save_writesMirrorFileToApplicationSupport() async throws {
        var config = CodexAdaptorConfig()
        config.wireAPI = .responses
        config.port = 15721

        await CodexAdaptorConfigStore.shared.save(config)

        // 验证镜像文件位置
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let expectedPath = appSupport.appendingPathComponent("com.apibypass.APIBypass/apibypass-config.json").path

        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath), "Mirror file should be at \(expectedPath)")
    }

    // MARK: - Test 2.2: UserDefaults 为空时能从镜像恢复

    func test_load_recoversFromMirrorFile_whenUserDefaultsEmpty() async throws {
        // 准备：先保存一个配置
        var config = CodexAdaptorConfig()
        config.wireAPI = .responses
        config.port = 19999
        let entry = CustomModelEntry(alias: "test-model", modelMappingId: UUID(), contextWindow: 128000)
        config.chatCustomModels = [entry]

        await CodexAdaptorConfigStore.shared.save(config)

        // 清空 UserDefaults 模拟重装后的状态
        UserDefaults.standard.removeObject(forKey: "com.apibypass.codexAdaptor")

        // 加载配置
        let loaded = await CodexAdaptorConfigStore.shared.load()

        // 验证从镜像恢复
        XCTAssertEqual(loaded.wireAPI, .responses, "Should recover wireAPI from mirror")
        XCTAssertEqual(loaded.port, 19999, "Should recover port from mirror")
        XCTAssertEqual(loaded.chatCustomModels.count, 1, "Should recover custom models from mirror")
        XCTAssertEqual(loaded.chatCustomModels.first?.alias, "test-model")
    }

    // MARK: - Test 2.3: 保存配置后能正确加载（往返）

    func test_saveAndLoad_roundTrip() async throws {
        var config = CodexAdaptorConfig()
        config.wireAPI = .chat
        config.port = 18080
        let entry = CustomModelEntry(alias: "roundtrip-model", modelMappingId: UUID(), contextWindow: 200000)
        config.responsesCustomModels = [entry]

        await CodexAdaptorConfigStore.shared.save(config)

        // 清除缓存以强制重新加载
        // 注意：由于 CodexAdaptorConfigStore 是 actor 且有缓存，
        // 我们通过清空 UserDefaults 并依赖镜像文件来测试往返
        UserDefaults.standard.removeObject(forKey: "com.apibypass.codexAdaptor")

        let loaded = await CodexAdaptorConfigStore.shared.load()

        XCTAssertEqual(loaded.wireAPI, .chat)
        XCTAssertEqual(loaded.port, 18080)
        XCTAssertEqual(loaded.responsesCustomModels.count, 1)
        XCTAssertEqual(loaded.responsesCustomModels.first?.alias, "roundtrip-model")
        XCTAssertEqual(loaded.responsesCustomModels.first?.contextWindow, 200000)
    }
}
