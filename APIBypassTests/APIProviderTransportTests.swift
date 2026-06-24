import XCTest
@testable import APIBypass

final class APIProviderTransportTests: XCTestCase {

    // MARK: - OpenAI 格式

    func testOpenAI_TransportableParameters() {
        let params = APIProvider.openai.transportableParameters
        XCTAssertTrue(params.contains(.temperature))
        XCTAssertTrue(params.contains(.topP))
        XCTAssertTrue(params.contains(.maxTokens))
        XCTAssertTrue(params.contains(.frequencyPenalty))
        XCTAssertTrue(params.contains(.presencePenalty))
        XCTAssertTrue(params.contains(.reasoningEffort))
    }

    func testOpenAI_TopK_NotTransportable() {
        let params = APIProvider.openai.transportableParameters
        XCTAssertFalse(params.contains(.topK))
    }

    func testOpenAI_BudgetTokens_NotTransportable() {
        let params = APIProvider.openai.transportableParameters
        XCTAssertFalse(params.contains(.budgetTokens))
    }

    func testOpenAI_MaxOutputTokens_NotTransportable() {
        let params = APIProvider.openai.transportableParameters
        XCTAssertFalse(params.contains(.maxOutputTokens))
    }

    // MARK: - Anthropic 格式

    func testAnthropic_TransportableParameters() {
        let params = APIProvider.anthropic.transportableParameters
        XCTAssertTrue(params.contains(.temperature))
        XCTAssertTrue(params.contains(.topP))
        XCTAssertTrue(params.contains(.topK))
        XCTAssertTrue(params.contains(.maxTokens))
        XCTAssertTrue(params.contains(.thinkingType))
        XCTAssertTrue(params.contains(.budgetTokens))
    }

    func testAnthropic_FrequencyPenalty_NotTransportable() {
        let params = APIProvider.anthropic.transportableParameters
        XCTAssertFalse(params.contains(.frequencyPenalty))
    }

    func testAnthropic_PresencePenalty_NotTransportable() {
        let params = APIProvider.anthropic.transportableParameters
        XCTAssertFalse(params.contains(.presencePenalty))
    }

    func testAnthropic_ReasoningEffort_NotTransportable() {
        let params = APIProvider.anthropic.transportableParameters
        XCTAssertFalse(params.contains(.reasoningEffort))
    }

    // MARK: - Responses 格式

    func testResponses_TransportableParameters() {
        let params = APIProvider.responses.transportableParameters
        XCTAssertTrue(params.contains(.temperature))
        XCTAssertTrue(params.contains(.topP))
        XCTAssertTrue(params.contains(.maxOutputTokens))
        XCTAssertTrue(params.contains(.frequencyPenalty))
        XCTAssertTrue(params.contains(.presencePenalty))
        XCTAssertTrue(params.contains(.reasoningEffort))
    }

    func testResponses_TopK_NotTransportable() {
        let params = APIProvider.responses.transportableParameters
        XCTAssertFalse(params.contains(.topK))
    }

    func testResponses_BudgetTokens_NotTransportable() {
        let params = APIProvider.responses.transportableParameters
        XCTAssertFalse(params.contains(.budgetTokens))
    }

    func testResponses_MaxTokens_NotTransportable() {
        let params = APIProvider.responses.transportableParameters
        XCTAssertFalse(params.contains(.maxTokens))
    }

    // MARK: - 差异对比

    func testTopK_OnlyAnthropic() {
        let openaiHasTopK = APIProvider.openai.transportableParameters.contains(.topK)
        let anthropicHasTopK = APIProvider.anthropic.transportableParameters.contains(.topK)
        let responsesHasTopK = APIProvider.responses.transportableParameters.contains(.topK)

        XCTAssertFalse(openaiHasTopK)
        XCTAssertTrue(anthropicHasTopK)
        XCTAssertFalse(responsesHasTopK)
    }

    func testFrequencyPenalty_NotAnthropic() {
        let openaiHasFreq = APIProvider.openai.transportableParameters.contains(.frequencyPenalty)
        let anthropicHasFreq = APIProvider.anthropic.transportableParameters.contains(.frequencyPenalty)
        let responsesHasFreq = APIProvider.responses.transportableParameters.contains(.frequencyPenalty)

        XCTAssertTrue(openaiHasFreq)
        XCTAssertFalse(anthropicHasFreq)
        XCTAssertTrue(responsesHasFreq)
    }
}
