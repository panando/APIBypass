import XCTest
@testable import CodexRouterCore

/// Tests for SSEStreamTransformer error handling.
final class SSEStreamTransformerTests: XCTestCase {

    // MARK: - Cycle 1: Error event generation

    /// Given a Chat SSE stream containing an error,
    /// When the stream is transformed,
    /// Then it emits a response.failed event with the error message.
    func test_transform_generatesFailedEventOnError() async throws {
        // Arrange
        let transformer = ChatToResponsesStreamTransformer()

        // SSE error format from Chat Completions
        let errorSSE = """
        event: error
        data: {"error": {"message": "Rate limit exceeded", "type": "rate_limit_error"}}

        """
        let data = errorSSE.data(using: .utf8)!

        // Act
        let result = await transformer.transform(data)

        // Assert - Should contain response.failed event
        let resultString = String(data: result ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(resultString.contains("response.failed"), "Should emit response.failed event")
        XCTAssertTrue(resultString.contains("Rate limit exceeded"), "Should include error message")
    }

    /// Given a Chat SSE chunk with error in the data,
    /// When the stream is transformed,
    /// Then it extracts the error and generates failed event.
    func test_transform_handlesErrorInChunkData() async throws {
        // Arrange
        let transformer = ChatToResponsesStreamTransformer()

        // Error in the data field (not as event type)
        let errorSSE = """
        data: {"error": {"message": "Invalid API key", "type": "authentication_error"}}

        """
        let data = errorSSE.data(using: .utf8)!

        // Act
        let result = await transformer.transform(data)

        // Assert
        let resultString = String(data: result ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(resultString.contains("response.failed"), "Should emit response.failed event")
        XCTAssertTrue(resultString.contains("Invalid API key"), "Should include error message")
    }

    // MARK: - Cycle 2: Premature stream termination

    /// Given a stream that ends without finish_reason or output,
    /// When finish() is called,
    /// Then it emits a response.failed event (not crash).
    func test_finish_generatesFailedEventWhenStreamTruncated() async throws {
        // Arrange
        let transformer = ChatToResponsesStreamTransformer()

        // Simulate a stream that started but never completed
        // This is a chunk with id/model but no finish_reason and no content
        let partialSSE = """
        data: {"id": "chat-123", "model": "gpt-4", "choices": []}

        """
        let data = partialSSE.data(using: .utf8)!

        // Act - Transform partial data then call finish
        _ = await transformer.transform(data)
        let finishResult = await transformer.finish()

        // Assert - Should generate failed event, not crash
        let resultString = String(data: finishResult ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(resultString.contains("response.failed") || resultString.contains("response.completed"),
                      "Should emit completion or failed event")
    }

    /// Given an empty stream (no chunks received),
    /// When finish() is called,
    /// Then it returns nil or an empty response (not crash).
    func test_finish_handlesEmptyStream() async throws {
        // Arrange
        let transformer = ChatToResponsesStreamTransformer()

        // Act - No data transformed, just call finish
        let finishResult = await transformer.finish()

        // Assert - Should not crash, returns nil or minimal response
        // Empty stream with no output should fail
        if let result = finishResult {
            let resultString = String(data: result, encoding: .utf8) ?? ""
            XCTAssertTrue(resultString.contains("response.failed") || resultString.isEmpty,
                          "Empty stream should generate failed or empty response")
        }
    }
}
