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

    // MARK: - Error Handling Tests

    func testTransformRequest_throwsOnInvalidJSON() {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "gpt-4o",
            apiProvider: .openai,
            baseURL: URL(string: "https://api.openai.com")!,
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
            apiProvider: .openai,
            baseURL: URL(string: "https://api.openai.com")!,
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
            apiProvider: .openai,
            baseURL: URL(string: "https://api.openai.com")!,
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
            apiProvider: .openai,
            baseURL: URL(string: "https://api.openai.com")!,
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
            apiProvider: .openai,
            baseURL: URL(string: "https://api.openai.com")!,
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
            apiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            parameters: InjectedParameters(thinking: ThinkingConfig(enabled: true))
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
}
