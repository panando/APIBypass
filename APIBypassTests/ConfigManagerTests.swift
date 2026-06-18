import XCTest
@testable import APIBypass

@MainActor
final class ConfigManagerTests: XCTestCase {
    private var configManager: ConfigManager!
    private let testDefaultsKey = "com.apibypass.test.mappings"

    override func setUp() async throws {
        try await super.setUp()
        configManager = ConfigManager()
        await configManager.refresh()
        // Clear shared store so each test starts with a clean slate
        for mapping in configManager.mappings {
            await configManager.delete(mapping.id)
        }
        for provider in configManager.providers {
            await configManager.deleteProvider(provider.id)
        }
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testDefaultsKey)
        super.tearDown()
    }

    func testEmptyInitially() {
        XCTAssertTrue(configManager.mappings.isEmpty)
    }

    func testAddMapping() async throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            providerConfigId: UUID(),
            parameters: .empty
        )

        await configManager.add(mapping)

        XCTAssertEqual(configManager.mappings.count, 1)
        XCTAssertEqual(configManager.mappings.first?.name, "Test")
    }

    func testUpdateMapping() async throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            providerConfigId: UUID(),
            parameters: .empty
        )

        await configManager.add(mapping)

        var updated = mapping
        updated.name = "Updated"
        await configManager.update(updated)

        XCTAssertEqual(configManager.mappings.first?.name, "Updated")
    }

    func testDeleteMapping() async throws {
        let mapping = ModelMapping(
            name: "Test",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            providerConfigId: UUID(),
            parameters: .empty
        )

        await configManager.add(mapping)
        await configManager.delete(mapping.id)

        XCTAssertTrue(configManager.mappings.isEmpty)
    }

    func testFindMappingByModel() async throws {
        let mapping1 = ModelMapping(
            name: "GPT-4",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            providerConfigId: UUID(),
            parameters: .empty
        )
        let mapping2 = ModelMapping(
            name: "GPT-3.5",
            incomingModel: "gpt-3.5-turbo",
            actualModel: "claude-haiku-4-5",
            providerConfigId: UUID(),
            parameters: .empty
        )

        await configManager.add(mapping1)
        await configManager.add(mapping2)

        let found = await configManager.findMapping(for: "gpt-4")
        XCTAssertEqual(found?.actualModel, "claude-sonnet-4-6")

        let notFound = await configManager.findMapping(for: "unknown")
        XCTAssertNil(notFound)
    }

    func testPersistence() async throws {
        let mapping = ModelMapping(
            name: "Persistent",
            incomingModel: "gpt-4",
            actualModel: "claude-sonnet-4-6",
            providerConfigId: UUID(),
            parameters: .empty
        )

        await configManager.add(mapping)

        // Create new ConfigManager instance, simulating app restart
        let newManager = ConfigManager()
        await newManager.refresh()
        XCTAssertEqual(newManager.mappings.count, 1)
        XCTAssertEqual(newManager.mappings.first?.name, "Persistent")
    }
}
