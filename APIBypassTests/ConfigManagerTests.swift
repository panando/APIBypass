import XCTest
@testable import APIBypass

final class ConfigManagerTests: XCTestCase {
    private var configManager: ConfigManager!
    private let testDefaultsKey = "com.apibypass.test.mappings"

    override func setUp() {
        super.setUp()
        configManager = ConfigManager(defaultsKey: testDefaultsKey)
        // Clear test data
        UserDefaults.standard.removeObject(forKey: testDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testDefaultsKey)
        super.tearDown()
    }

    func testEmptyInitially() {
        XCTAssertTrue(configManager.mappings.isEmpty)
    }

    func testAddMapping() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            apiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            parameters: .empty
        )

        configManager.add(mapping)

        XCTAssertEqual(configManager.mappings.count, 1)
        XCTAssertEqual(configManager.mappings.first?.name, "Test")
    }

    func testUpdateMapping() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            apiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            parameters: .empty
        )

        configManager.add(mapping)

        var updated = mapping
        updated.name = "Updated"
        configManager.update(updated)

        XCTAssertEqual(configManager.mappings.first?.name, "Updated")
    }

    func testDeleteMapping() throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            apiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            parameters: .empty
        )

        configManager.add(mapping)
        configManager.delete(mapping.id)

        XCTAssertTrue(configManager.mappings.isEmpty)
    }

    func testFindMappingByModel() throws {
        let mapping1 = ModelMapping(
            name: "GPT-4",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            apiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            parameters: .empty
        )
        let mapping2 = ModelMapping(
            name: "GPT-3.5",
            incomingModel: "gpt-3.5-turbo",
            actualModel: "claude-haiku-4-5",
            apiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            parameters: .empty
        )

        configManager.add(mapping1)
        configManager.add(mapping2)

        let found = configManager.findMapping(for: "gpt-4")
        XCTAssertEqual(found?.actualModel, "claude-sonnet-4-6")

        let notFound = configManager.findMapping(for: "unknown")
        XCTAssertNil(notFound)
    }

    func testPersistence() throws {
        let mapping = ModelMapping(
            name: "Persistent",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            apiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            parameters: .empty
        )

        configManager.add(mapping)

        // Create new ConfigManager instance, simulating app restart
        let newManager = ConfigManager(defaultsKey: testDefaultsKey)
        XCTAssertEqual(newManager.mappings.count, 1)
        XCTAssertEqual(newManager.mappings.first?.name, "Persistent")
    }
}
