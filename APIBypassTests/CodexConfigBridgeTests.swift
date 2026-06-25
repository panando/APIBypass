import XCTest
@testable import APIBypass

final class CodexConfigBridgeTests: XCTestCase {

    // MARK: - Test 2.1: 按协议过滤模型映射

    func test_availableMappingsForProtocol_filtersChatModels() async {
        await MainActor.run {
            let configManager = ConfigManager()

            // 创建 Chat Provider
            let chatProvider = ProviderConfig(
                name: "Chat Provider",
                apiProvider: .openai,
                baseURL: URL(string: "https://api.example.com")!
            )

            // 创建 Responses Provider
            let responsesProvider = ProviderConfig(
                name: "Responses Provider",
                apiProvider: .responses,
                baseURL: URL(string: "https://responses.example.com")!
            )

            configManager.providers = [chatProvider, responsesProvider]

            // 创建模型映射
            let chatMapping = ModelMapping(
                name: "Chat Model",
                incomingModel: "chat-model",
                actualModel: "actual-chat",
                providerConfigId: chatProvider.id,
                parameters: .empty
            )

            let responsesMapping = ModelMapping(
                name: "Responses Model",
                incomingModel: "responses-model",
                actualModel: "actual-responses",
                providerConfigId: responsesProvider.id,
                parameters: .empty
            )

            configManager.mappings = [chatMapping, responsesMapping]

            // 测试 Chat 协议过滤
            let chatMappings = CodexConfigBridge.availableMappings(for: .chat, from: configManager)
            XCTAssertEqual(chatMappings.count, 1)
            XCTAssertEqual(chatMappings.first?.incomingModel, "chat-model")

            // 测试 Responses 协议过滤
            let responsesMappings = CodexConfigBridge.availableMappings(for: .responses, from: configManager)
            XCTAssertEqual(responsesMappings.count, 1)
            XCTAssertEqual(responsesMappings.first?.incomingModel, "responses-model")
        }
    }

    func test_availableMappingsForProtocol_returnsEmpty_whenNoProviderForProtocol() async {
        await MainActor.run {
            let configManager = ConfigManager()

            // 只有 Chat Provider
            let chatProvider = ProviderConfig(
                name: "Chat Provider",
                apiProvider: .openai,
                baseURL: URL(string: "https://api.example.com")!
            )
            configManager.providers = [chatProvider]

            let chatMapping = ModelMapping(
                name: "Chat Model",
                incomingModel: "chat-model",
                actualModel: "actual-chat",
                providerConfigId: chatProvider.id,
                parameters: .empty
            )
            configManager.mappings = [chatMapping]

            // 请求 Responses 协议的映射
            let responsesMappings = CodexConfigBridge.availableMappings(for: .responses, from: configManager)
            XCTAssertEqual(responsesMappings.count, 0)
        }
    }

    func test_availableMappingsForProtocol_includesAnthropicProvider() async {
        await MainActor.run {
            let configManager = ConfigManager()

            // 创建 Anthropic Provider (也应该属于 Chat 协议)
            let anthropicProvider = ProviderConfig(
                name: "Anthropic Provider",
                apiProvider: .anthropic,
                baseURL: URL(string: "https://api.anthropic.com")!
            )
            configManager.providers = [anthropicProvider]

            let anthropicMapping = ModelMapping(
                name: "Anthropic Model",
                incomingModel: "anthropic-model",
                actualModel: "claude-sonnet-4-6",
                providerConfigId: anthropicProvider.id,
                parameters: .empty
            )
            configManager.mappings = [anthropicMapping]

            // Anthropic 也应该出现在 Chat 协议的列表中
            let chatMappings = CodexConfigBridge.availableMappings(for: .chat, from: configManager)
            XCTAssertEqual(chatMappings.count, 1)
            XCTAssertEqual(chatMappings.first?.incomingModel, "anthropic-model")
        }
    }

    func test_availableMappingsForProtocol_onlyReturnsEnabledMappings() async {
        await MainActor.run {
            let configManager = ConfigManager()

            let chatProvider = ProviderConfig(
                name: "Chat Provider",
                apiProvider: .openai,
                baseURL: URL(string: "https://api.example.com")!
            )
            configManager.providers = [chatProvider]

            let enabledMapping = ModelMapping(
                name: "Enabled Model",
                incomingModel: "enabled-model",
                actualModel: "actual-enabled",
                providerConfigId: chatProvider.id,
                parameters: .empty,
                isEnabled: true
            )

            let disabledMapping = ModelMapping(
                name: "Disabled Model",
                incomingModel: "disabled-model",
                actualModel: "actual-disabled",
                providerConfigId: chatProvider.id,
                parameters: .empty,
                isEnabled: false
            )

            configManager.mappings = [enabledMapping, disabledMapping]

            let chatMappings = CodexConfigBridge.availableMappings(for: .chat, from: configManager)
            XCTAssertEqual(chatMappings.count, 1)
            XCTAssertEqual(chatMappings.first?.incomingModel, "enabled-model")
        }
    }

    // MARK: - buildCatalogEntries: fallback when customModels is empty

    func test_buildCatalogEntries_fallsBackToAllProtocolMatchingMappings_whenCustomModelsEmpty() {
        let chatProvider = ProviderConfig(
            name: "Chat Provider",
            apiProvider: .openai,
            baseURL: URL(string: "https://api.example.com")!
        )

        let chatMapping = ModelMapping(
            name: "Chat Model",
            incomingModel: "gpt-4o",
            actualModel: "actual-gpt-4o",
            providerConfigId: chatProvider.id,
            parameters: .empty,
            isEnabled: true
        )

        let entries = CodexConfigBridge.buildCatalogEntries(
            customModels: [],
            mappings: [chatMapping],
            providers: [chatProvider],
            wireAPI: .chat
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.model, "gpt-4o")
        XCTAssertEqual(entries.first?.displayName, "gpt-4o")
    }

    // MARK: - buildCatalogEntries: non-empty customModels uses existing resolution

    func test_buildCatalogEntries_usesCustomModelAlias_whenCustomModelsNonEmpty() {
        let chatProvider = ProviderConfig(
            name: "Chat Provider",
            apiProvider: .openai,
            baseURL: URL(string: "https://api.example.com")!
        )

        let chatMapping = ModelMapping(
            name: "Chat Model",
            incomingModel: "gpt-4o",
            actualModel: "actual-gpt-4o",
            providerConfigId: chatProvider.id,
            parameters: .empty,
            isEnabled: true
        )

        let customEntry = CustomModelEntry(
            alias: "My GPT",
            modelMappingId: chatMapping.id,
            contextWindow: 200000
        )

        let entries = CodexConfigBridge.buildCatalogEntries(
            customModels: [customEntry],
            mappings: [chatMapping],
            providers: [chatProvider],
            wireAPI: .chat
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.model, "gpt-4o")
        XCTAssertEqual(entries.first?.displayName, "My GPT")
        XCTAssertEqual(entries.first?.contextWindow, 200000)
    }

    func test_buildCatalogEntries_usesIncomingModel_whenAliasEmpty() {
        let chatProvider = ProviderConfig(
            name: "Chat Provider",
            apiProvider: .openai,
            baseURL: URL(string: "https://api.example.com")!
        )
        let chatMapping = ModelMapping(
            name: "Chat Model",
            incomingModel: "gpt-4o",
            actualModel: "actual-gpt-4o",
            providerConfigId: chatProvider.id,
            parameters: .empty
        )
        let customEntry = CustomModelEntry(
            alias: "",
            modelMappingId: chatMapping.id,
            contextWindow: nil
        )

        let entries = CodexConfigBridge.buildCatalogEntries(
            customModels: [customEntry],
            mappings: [chatMapping],
            providers: [chatProvider],
            wireAPI: .chat
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.model, "gpt-4o")
        XCTAssertEqual(entries.first?.displayName, "gpt-4o")
    }

    // MARK: - buildCatalogEntries: protocol filter on fallback

    func test_buildCatalogEntries_fallbackFiltersByWireAPIProtocol() {
        let chatProvider = ProviderConfig(
            name: "Chat Provider",
            apiProvider: .openai,
            baseURL: URL(string: "https://api.example.com")!
        )
        let responsesProvider = ProviderConfig(
            name: "Responses Provider",
            apiProvider: .responses,
            baseURL: URL(string: "https://responses.example.com")!
        )

        let chatMapping = ModelMapping(
            name: "Chat Model",
            incomingModel: "gpt-4o",
            actualModel: "actual-gpt-4o",
            providerConfigId: chatProvider.id,
            parameters: .empty
        )
        let responsesMapping = ModelMapping(
            name: "Responses Model",
            incomingModel: "o3-pro",
            actualModel: "actual-o3-pro",
            providerConfigId: responsesProvider.id,
            parameters: .empty
        )

        // Chat protocol should exclude responses provider's models
        let chatEntries = CodexConfigBridge.buildCatalogEntries(
            customModels: [],
            mappings: [chatMapping, responsesMapping],
            providers: [chatProvider, responsesProvider],
            wireAPI: .chat
        )
        XCTAssertEqual(chatEntries.count, 1)
        XCTAssertEqual(chatEntries.first?.model, "gpt-4o")

        // Responses protocol should exclude chat provider's models
        let responsesEntries = CodexConfigBridge.buildCatalogEntries(
            customModels: [],
            mappings: [chatMapping, responsesMapping],
            providers: [chatProvider, responsesProvider],
            wireAPI: .responses
        )
        XCTAssertEqual(responsesEntries.count, 1)
        XCTAssertEqual(responsesEntries.first?.model, "o3-pro")
    }
}
