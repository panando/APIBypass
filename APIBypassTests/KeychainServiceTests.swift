import XCTest
@testable import APIBypass

final class KeychainServiceTests: XCTestCase {
    private var keychain: KeychainService!
    private let testService = "com.apibypass.test"

    override func setUp() {
        super.setUp()
        keychain = KeychainService(service: testService)
        // Clean up any existing test data
        try? keychain.delete(forKey: "test-key")
    }

    override func tearDown() {
        try? keychain.delete(forKey: "test-key")
        super.tearDown()
    }

    func testSaveAndRetrieve() throws {
        try keychain.save("secret-value", forKey: "test-key")
        let retrieved = try keychain.retrieve(forKey: "test-key")
        XCTAssertEqual(retrieved, "secret-value")
    }

    func testRetrieveNonExistentThrows() {
        XCTAssertThrowsError(try keychain.retrieve(forKey: "non-existent"))
    }

    func testUpdateExistingKey() throws {
        try keychain.save("value1", forKey: "test-key")
        try keychain.save("value2", forKey: "test-key")
        let retrieved = try keychain.retrieve(forKey: "test-key")
        XCTAssertEqual(retrieved, "value2")
    }

    func testDelete() throws {
        try keychain.save("value", forKey: "test-key")
        try keychain.delete(forKey: "test-key")
        XCTAssertThrowsError(try keychain.retrieve(forKey: "test-key"))
    }

    func testDeleteNonExistentDoesNotThrow() {
        XCTAssertNoThrow(try keychain.delete(forKey: "non-existent"))
    }
}
