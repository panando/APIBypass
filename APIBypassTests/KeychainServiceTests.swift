import XCTest
@testable import APIBypass

final class KeychainServiceTests: XCTestCase {
    private var keychain: KeychainService!
    private let testService = "com.apibypass.test"

    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainService(service: testService)
        // Clean up any existing test data
        try? await keychain.delete(forKey: "test-key")
    }

    override func tearDown() async throws {
        try? await keychain.delete(forKey: "test-key")
        try await super.tearDown()
    }

    func testSaveAndRetrieve() async throws {
        try await keychain.save("secret-value", forKey: "test-key")
        let retrieved = try await keychain.retrieve(forKey: "test-key")
        XCTAssertEqual(retrieved, "secret-value")
    }

    func testRetrieveNonExistentThrows() async {
        await XCTAssertThrowsErrorAsync(try await keychain.retrieve(forKey: "non-existent"))
    }

    func testUpdateExistingKey() async throws {
        try await keychain.save("value1", forKey: "test-key")
        try await keychain.save("value2", forKey: "test-key")
        let retrieved = try await keychain.retrieve(forKey: "test-key")
        XCTAssertEqual(retrieved, "value2")
    }

    func testDelete() async throws {
        try await keychain.save("value", forKey: "test-key")
        try await keychain.delete(forKey: "test-key")
        await XCTAssertThrowsErrorAsync(try await keychain.retrieve(forKey: "test-key"))
    }

    func testDeleteNonExistentDoesNotThrow() async {
        await XCTAssertNoThrowAsync(try await keychain.delete(forKey: "non-existent"))
    }
}

// MARK: - Async XCTest Helpers

extension XCTestCase {
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            // Expected
        }
    }

    func XCTAssertNoThrowAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
        } catch {
            XCTFail(message() + " - threw error: \(error)", file: file, line: line)
        }
    }
}
