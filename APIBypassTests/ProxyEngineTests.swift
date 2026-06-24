import XCTest
@testable import APIBypass

extension ProxyError: Equatable {
    public static func == (lhs: ProxyError, rhs: ProxyError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidJSON, .invalidJSON):
            return true
        case let (.upstreamError(code1, data1), .upstreamError(code2, data2)):
            return code1 == code2 && data1 == data2
        default:
            return false
        }
    }
}

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
            providerConfigId: UUID(),
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
            providerConfigId: UUID(),
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
            providerConfigId: UUID(),
            parameters: InjectedParameters(maxTokens: 1000)
        )

        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [["role": "user", "content": "Hello"]],
            "temperature": 0.5  // Client-provided parameter
        ]
        let data = try JSONSerialization.data(withJSONObject: requestBody)

        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]

        // Preserve client parameter
        XCTAssertEqual(json["temperature"] as? Double, 0.5)
        // Inject new parameter
        XCTAssertEqual(json["max_tokens"] as? Int, 1000)
    }

    // MARK: - Anthropic Format Tests

    func testTransformAnthropicRequest_injectsThinking() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "claude",
            actualModel: "claude-sonnet-4-6",
            providerConfigId: UUID(),
            parameters: InjectedParameters(thinking: ThinkingConfig(enabled: true), thinkingOverrideEnabled: true)
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
        XCTAssertNil(thinking["budget_tokens"])
    }

    func testTransformAnthropicRequest_disablesThinking() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "claude",
            actualModel: "claude-sonnet-4-6",
            providerConfigId: UUID(),
            parameters: InjectedParameters(thinking: ThinkingConfig(enabled: false), thinkingOverrideEnabled: true)
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
            providerConfigId: UUID(),
            parameters: InjectedParameters(temperature: 0.8, maxTokens: 2048)
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

    // MARK: - Error Handling Tests

    func testTransformRequest_throwsOnInvalidJSON() {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "gpt-4o",
            providerConfigId: UUID(),
            parameters: .empty
        )

        let invalidData = "not json".data(using: .utf8)!

        XCTAssertThrowsError(try engine.transformRequest(data: invalidData, mapping: mapping, format: .openai)) { error in
            XCTAssertTrue(error is ProxyError)
            if let proxyError = error as? ProxyError {
                XCTAssertEqual(proxyError, .invalidJSON)
            }
        }
    }

    // MARK: - Parameter Injection Tests

    func testTransformRequest_injectsTopP() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "gpt-4o",
            providerConfigId: UUID(),
            parameters: InjectedParameters(topP: 0.9)
        )

        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [["role": "user", "content": "Hello"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: requestBody)

        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]

        XCTAssertEqual(json["top_p"] as? Double, 0.9)
    }

    func testTransformRequest_injectsFrequencyPenalty() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "gpt-4o",
            providerConfigId: UUID(),
            parameters: InjectedParameters(frequencyPenalty: 0.5)
        )

        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [["role": "user", "content": "Hello"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: requestBody)

        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]

        XCTAssertEqual(json["frequency_penalty"] as? Double, 0.5)
    }

    func testTransformRequest_injectsPresencePenalty() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "gpt-4o",
            providerConfigId: UUID(),
            parameters: InjectedParameters(presencePenalty: 0.3)
        )

        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [["role": "user", "content": "Hello"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: requestBody)

        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]

        XCTAssertEqual(json["presence_penalty"] as? Double, 0.3)
    }

    func testTransformRequest_injectsAllParameters() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "gpt-4o",
            providerConfigId: UUID(),
            parameters: InjectedParameters(
                temperature: 0.7,
                maxTokens: 2000,
                topP: 0.95,
                frequencyPenalty: 0.2,
                presencePenalty: 0.1
            )
        )

        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [["role": "user", "content": "Hello"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: requestBody)

        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]

        XCTAssertEqual(json["temperature"] as? Double, 0.7)
        XCTAssertEqual(json["max_tokens"] as? Int, 2000)
        XCTAssertEqual(json["top_p"] as? Double, 0.95)
        XCTAssertEqual(json["frequency_penalty"] as? Double, 0.2)
        XCTAssertEqual(json["presence_penalty"] as? Double, 0.1)
    }

    // MARK: - Thinking without budget tests

    func testTransformAnthropicRequest_thinkingWithoutBudget() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "claude",
            actualModel: "claude-sonnet-4-6",
            providerConfigId: UUID(),
            parameters: InjectedParameters(thinking: ThinkingConfig(enabled: true), thinkingOverrideEnabled: true)
        )

        let requestBody: [String: Any] = [
            "model": "claude",
            "messages": [["role": "user", "content": "Hello"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: requestBody)

        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .anthropic)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]

        let thinking = json["thinking"] as! [String: Any]
        XCTAssertEqual(thinking["type"] as? String, "enabled")
        XCTAssertNil(thinking["budget_tokens"])
    }

    // MARK: - OpenAI thinking protocol tests

    func testTransformOpenAIRequest_enableThinkingProtocol() throws {
        let mapping = ModelMapping(
            name: "Test", incomingModel: "glm", actualModel: "glm-5.2",
            providerConfigId: UUID(),
            parameters: InjectedParameters(
                thinking: ThinkingConfig(enabled: true, thinkingProtocol: .enableThinking),
                thinkingOverrideEnabled: true
            )
        )
        let body: [String: Any] = ["model": "glm", "messages": [["role": "user", "content": "hi"]]]
        let data = try JSONSerialization.data(withJSONObject: body)
        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
        XCTAssertEqual(json["enable_thinking"] as? Bool, true)
        XCTAssertNil(json["thinking_budget"])
    }

    func testTransformOpenAIRequest_enableThinkingProtocolOff() throws {
        let mapping = ModelMapping(
            name: "Test", incomingModel: "glm", actualModel: "glm-5.2",
            providerConfigId: UUID(),
            parameters: InjectedParameters(
                thinking: ThinkingConfig(enabled: false, thinkingProtocol: .enableThinking),
                thinkingOverrideEnabled: true
            )
        )
        let body: [String: Any] = ["model": "glm", "messages": [["role": "user", "content": "hi"]]]
        let data = try JSONSerialization.data(withJSONObject: body)
        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
        XCTAssertEqual(json["enable_thinking"] as? Bool, false)
    }

    func testTransformOpenAIRequest_reasoningEffortProtocol() throws {
        let mapping = ModelMapping(
            name: "Test", incomingModel: "o3", actualModel: "o3-mini",
            providerConfigId: UUID(),
            parameters: InjectedParameters(
                thinking: ThinkingConfig(enabled: true, thinkingProtocol: .reasoningEffort, effort: "high"),
                thinkingOverrideEnabled: true
            )
        )
        let body: [String: Any] = ["model": "o3", "messages": [["role": "user", "content": "hi"]]]
        let data = try JSONSerialization.data(withJSONObject: body)
        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
        XCTAssertEqual(json["reasoning_effort"] as? String, "high")
        XCTAssertNil(json["enable_thinking"])
    }

    func testTransformOpenAIRequest_noneProtocolEmitsNothing() throws {
        let mapping = ModelMapping(
            name: "Test", incomingModel: "ds", actualModel: "deepseek-r1",
            providerConfigId: UUID(),
            parameters: InjectedParameters(
                thinking: ThinkingConfig(enabled: true, thinkingProtocol: .reasoningEffort),
                thinkingOverrideEnabled: true
            )
        )
        let body: [String: Any] = ["model": "ds", "messages": [["role": "user", "content": "hi"]]]
        let data = try JSONSerialization.data(withJSONObject: body)
        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
        XCTAssertNil(json["enable_thinking"])
        XCTAssertNil(json["reasoning_effort"])
        XCTAssertNil(json["thinking"])
    }

    // MARK: - Cross-format (Anthropic client → OpenAI upstream) thinking protocol tests

    func testAnthropicToOpenAI_reasoningEffortProtocol() throws {
        let translator = FormatTranslator()
        let anthropicBody: [String: Any] = [
            "model": "o3",
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1024,
            "thinking": ["type": "enabled"]
        ]
        let data = try JSONSerialization.data(withJSONObject: anthropicBody)
        let translated = try translator.translateRequest(
            data, from: .anthropic, to: .openai,
            thinkingConfig: ThinkingConfig(enabled: true, thinkingProtocol: .reasoningEffort, effort: "high")
        )
        let json = try JSONSerialization.jsonObject(with: translated) as! [String: Any]
        XCTAssertEqual(json["reasoning_effort"] as? String, "high")
        XCTAssertNil(json["enable_thinking"])
        XCTAssertNil(json["thinking"])
    }

    func testAnthropicToOpenAI_noneProtocolStripsThinking() throws {
        let translator = FormatTranslator()
        let anthropicBody: [String: Any] = [
            "model": "ds", "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1024,
            "thinking": ["type": "enabled"]
        ]
        let data = try JSONSerialization.data(withJSONObject: anthropicBody)
        let translated = try translator.translateRequest(
            data, from: .anthropic, to: .openai,
            thinkingConfig: ThinkingConfig(enabled: true, thinkingProtocol: .reasoningEffort)
        )
        let json = try JSONSerialization.jsonObject(with: translated) as! [String: Any]
        XCTAssertNil(json["enable_thinking"])
        XCTAssertNil(json["reasoning_effort"])
        XCTAssertNil(json["thinking"])
    }

    func testAnthropicToOpenAI_anthropicNativePreservesThinking() throws {
        let translator = FormatTranslator()
        let anthropicBody: [String: Any] = [
            "model": "claude", "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1024,
            "thinking": ["type": "enabled", "budget_tokens": 5000]
        ]
        let data = try JSONSerialization.data(withJSONObject: anthropicBody)
        let translated = try translator.translateRequest(
            data, from: .anthropic, to: .openai,
            thinkingConfig: ThinkingConfig(enabled: true, budgetTokens: 5000, thinkingProtocol: .thinkingType)
        )
        let json = try JSONSerialization.jsonObject(with: translated) as! [String: Any]
        let thinking = json["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["type"] as? String, "enabled")
        XCTAssertEqual(thinking?["budget_tokens"] as? Int, 5000)
        XCTAssertNil(json["enable_thinking"])
    }

    func testAnthropicToOpenAI_enableThinkingOffEmitsFalse() throws {
        let translator = FormatTranslator()
        let anthropicBody: [String: Any] = [
            "model": "glm", "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1024,
            "thinking": ["type": "disabled"]
        ]
        let data = try JSONSerialization.data(withJSONObject: anthropicBody)
        let translated = try translator.translateRequest(
            data, from: .anthropic, to: .openai,
            thinkingConfig: ThinkingConfig(enabled: false, thinkingProtocol: .enableThinking)
        )
        let json = try JSONSerialization.jsonObject(with: translated) as! [String: Any]
        XCTAssertEqual(json["enable_thinking"] as? Bool, false)
    }

    // MARK: - Cross-format (OpenAI client → Anthropic upstream) reasoning_effort tests

    func testOpenAIToAnthropic_reasoningEffort() throws {
        let translator = FormatTranslator()
        let oaiBody: [String: Any] = [
            "model": "o3",
            "messages": [["role": "user", "content": "hi"]],
            "reasoning_effort": "high"
        ]
        let data = try JSONSerialization.data(withJSONObject: oaiBody)
        let translated = try translator.translateRequest(data, from: .openai, to: .anthropic)
        let json = try JSONSerialization.jsonObject(with: translated) as! [String: Any]
        let thinking = json["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["type"] as? String, "enabled")
        XCTAssertNil(json["reasoning_effort"])
    }

    // MARK: - Auto-inject max_tokens for Anthropic format

    func testTransformAnthropicRequest_autoInjectsMaxTokens() throws {
        // Anthropic API requires max_tokens, should auto-inject when missing
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "claude",
            actualModel: "claude-sonnet-4-6",
            providerConfigId: UUID(),
            parameters: .empty  // No maxTokens configured
        )

        let requestBody: [String: Any] = [
            "model": "claude",
            "messages": [["role": "user", "content": "Hello"]]
            // No max_tokens provided
        ]
        let data = try JSONSerialization.data(withJSONObject: requestBody)

        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .anthropic)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]

        // Should auto-inject default max_tokens
        XCTAssertNotNil(json["max_tokens"], "max_tokens should be auto-injected for Anthropic format")
        XCTAssertGreaterThan(json["max_tokens"] as? Int ?? 0, 0)
    }

    func testTransformAnthropicRequest_preservesExistingMaxTokens() throws {
        // If max_tokens is already provided, don't override
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "claude",
            actualModel: "claude-sonnet-4-6",
            providerConfigId: UUID(),
            parameters: .empty
        )

        let requestBody: [String: Any] = [
            "model": "claude",
            "messages": [["role": "user", "content": "Hello"]],
            "max_tokens": 2048  // Client-provided
        ]
        let data = try JSONSerialization.data(withJSONObject: requestBody)

        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .anthropic)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]

        // Should preserve client-provided value
        XCTAssertEqual(json["max_tokens"] as? Int, 2048)
    }

    func testTransformOpenAIRequest_doesNotAutoInjectMaxTokens() throws {
        // OpenAI format should NOT auto-inject max_tokens
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "gpt-4o",
            providerConfigId: UUID(),
            parameters: .empty
        )

        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [["role": "user", "content": "Hello"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: requestBody)

        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]

        // Should NOT auto-inject for OpenAI format
        XCTAssertNil(json["max_tokens"])
    }
}
