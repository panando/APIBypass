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
}
