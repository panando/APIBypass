import XCTest
@testable import APIBypass

final class ModelMappingTests: XCTestCase {

    // MARK: - APIProvider Tests

    func testAPIProvider_rawValue() {
        XCTAssertEqual(APIProvider.openai.rawValue, "openai")
        XCTAssertEqual(APIProvider.anthropic.rawValue, "anthropic")
    }

    func testAPIProvider_canDecodeFromJSON() throws {
        let json = """
        {"provider": "openai"}
        """.data(using: .utf8)!

        struct Container: Codable {
            let provider: APIProvider
        }

        let container = try JSONDecoder().decode(Container.self, from: json)
        XCTAssertEqual(container.provider, .openai)
    }

    // MARK: - ThinkingConfig Tests

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

    func testThinkingConfigCodableWithProtocol() throws {
        let config = ThinkingConfig(
            enabled: true,
            budgetTokens: 5000,
            thinkingProtocol: .none,
            effort: "high"
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ThinkingConfig.self, from: data)
        XCTAssertEqual(decoded.enabled, true)
        XCTAssertEqual(decoded.budgetTokens, 5000)
        XCTAssertEqual(decoded.thinkingProtocol, .none)
        XCTAssertEqual(decoded.effort, "high")
    }

    func testThinkingConfigBackwardCompatOldReasoningEffort() throws {
        // 旧版本 protocol="reasoning_effort" 应迁移到 .none
        let json = #"{"enabled":true,"budgetTokens":5000,"protocol":"reasoning_effort","effort":"high"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ThinkingConfig.self, from: json)
        XCTAssertEqual(decoded.thinkingProtocol, .none)
        XCTAssertEqual(decoded.effort, "high")
    }

    func testThinkingConfigBackwardCompatOldFormat() throws {
        // Old format: no protocol/effort fields
        let json = #"{"enabled":true,"budgetTokens":10000}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ThinkingConfig.self, from: json)
        XCTAssertEqual(decoded.enabled, true)
        XCTAssertEqual(decoded.budgetTokens, 10000)
        XCTAssertEqual(decoded.thinkingProtocol, .enable_thinking) // default fallback
        XCTAssertNil(decoded.effort)
    }

    // MARK: - ThinkingConfig.ThinkingProtocol.infer Tests

    func testInferProtocolGLM() {
        let p = ThinkingConfig.ThinkingProtocol.infer(baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-5.2")
        XCTAssertEqual(p, .anthropic_native)
    }

    func testInferProtocolOpenAIOSeries() {
        let p = ThinkingConfig.ThinkingProtocol.infer(baseURL: "https://api.openai.com/v1", model: "o3-mini")
        XCTAssertEqual(p, .none)
    }

    func testInferProtocolDeepSeekReasoner() {
        let p = ThinkingConfig.ThinkingProtocol.infer(baseURL: "https://api.deepseek.com/v1", model: "deepseek-r1")
        XCTAssertEqual(p, .none)
    }

    func testInferProtocolAnthropic() {
        let p = ThinkingConfig.ThinkingProtocol.infer(baseURL: "https://api.anthropic.com", model: "claude-sonnet-4-6")
        XCTAssertEqual(p, .anthropic_native)
    }

    // MARK: - InjectedParameters Tests

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

    // MARK: - ModelMapping Tests

    func testModelMapping_fullEncoding() throws {
        let mapping = ModelMapping(
            id: UUID(),
            name: "Test Config",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            providerConfigId: UUID(),
            parameters: InjectedParameters(temperature: 0.5, thinking: ThinkingConfig(enabled: true, budgetTokens: 5000)),
            isEnabled: true
        )

        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(ModelMapping.self, from: data)

        XCTAssertEqual(decoded.name, "Test Config")
        XCTAssertEqual(decoded.incomingModel, "gpt-4")
        XCTAssertEqual(decoded.actualModel, "claude-sonnet-4-6")
        XCTAssertEqual(decoded.providerConfigId, mapping.providerConfigId)
        XCTAssertTrue(decoded.isEnabled)
    }

    func testModelMapping_matchesIncomingModel() {
        let mapping = ModelMapping(
            id: UUID(),
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            providerConfigId: UUID(),
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
            providerConfigId: UUID(),
            parameters: .empty,
            isEnabled: false
        )

        XCTAssertFalse(mapping.matches(model: "gpt-4"))
    }
}
