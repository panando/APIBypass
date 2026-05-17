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
