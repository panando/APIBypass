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
            parameters: InjectedParameters(thinking: ThinkingConfig(enabled: true, budgetTokens: 10000), thinkingOverrideEnabled: true)
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
                thinking: ThinkingConfig(enabled: true, budgetTokens: 8000, thinkingProtocol: .enable_thinking),
                thinkingOverrideEnabled: true
            )
        )
        let body: [String: Any] = ["model": "glm", "messages": [["role": "user", "content": "hi"]]]
        let data = try JSONSerialization.data(withJSONObject: body)
        let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
        let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
        XCTAssertEqual(json["enable_thinking"] as? Bool, true)
        XCTAssertEqual(json["thinking_budget"] as? Int, 8000)
    }

    func testTransformOpenAIRequest_enableThinkingProtocolOff() throws {
        let mapping = ModelMapping(
            name: "Test", incomingModel: "glm", actualModel: "glm-5.2",
            providerConfigId: UUID(),
            parameters: InjectedParameters(
                thinking: ThinkingConfig(enabled: false, thinkingProtocol: .enable_thinking),
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
                thinking: ThinkingConfig(enabled: true, thinkingProtocol: .reasoning_effort, effort: "high"),
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
                thinking: ThinkingConfig(enabled: true, thinkingProtocol: .none),
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
}
