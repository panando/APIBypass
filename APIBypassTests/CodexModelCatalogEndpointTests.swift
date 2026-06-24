import XCTest
import CodexRouterCore
@testable import APIBypass

final class CodexModelCatalogEndpointTests: XCTestCase {

    /// Nil catalog → empty models array, status "ok".
    func test_makeModelCatalogBody_nilCatalog_returnsEmptyModels() throws {
        let data = CodexRequestHandler.makeModelCatalogBody(catalog: nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["status"] as? String, "ok")
        let models = try XCTUnwrap(json["models"] as? [Any])
        XCTAssertEqual(models.count, 0)
    }

    /// Empty catalog → empty models array.
    func test_makeModelCatalogBody_emptyCatalog_returnsEmptyModels() throws {
        let catalog = ModelCatalog(models: [])
        let data = CodexRequestHandler.makeModelCatalogBody(catalog: catalog)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["status"] as? String, "ok")
        let models = try XCTUnwrap(json["models"] as? [Any])
        XCTAssertEqual(models.count, 0)
    }

    /// Entry with displayName → uses displayName.
    func test_makeModelCatalogBody_entryWithDisplayName_usesDisplayName() throws {
        let catalog = ModelCatalog(models: [
            ModelCatalogEntry(model: "gpt-5.5", displayName: "My Alias", contextWindow: 128000)
        ])
        let data = CodexRequestHandler.makeModelCatalogBody(catalog: catalog)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let models = try XCTUnwrap(json["models"] as? [[String: Any]])
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0]["model"] as? String, "gpt-5.5")
        XCTAssertEqual(models[0]["displayName"] as? String, "My Alias")
    }

    /// Entry without displayName → displayName falls back to model slug.
    func test_makeModelCatalogBody_entryWithoutDisplayName_usesModelSlug() throws {
        let catalog = ModelCatalog(models: [
            ModelCatalogEntry(model: "claude-sonnet-4-6", displayName: nil, contextWindow: nil)
        ])
        let data = CodexRequestHandler.makeModelCatalogBody(catalog: catalog)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entry = try XCTUnwrap((json["models"] as? [[String: Any]])?.first)
        XCTAssertEqual(entry["model"] as? String, "claude-sonnet-4-6")
        XCTAssertEqual(entry["displayName"] as? String, "claude-sonnet-4-6")
    }

    /// Multiple entries preserve order.
    func test_makeModelCatalogBody_multipleEntries_preservesOrder() throws {
        let catalog = ModelCatalog(models: [
            ModelCatalogEntry(model: "model-a", displayName: "A", contextWindow: nil),
            ModelCatalogEntry(model: "model-b", displayName: "B", contextWindow: nil)
        ])
        let data = CodexRequestHandler.makeModelCatalogBody(catalog: catalog)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let models = try XCTUnwrap(json["models"] as? [[String: Any]])
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models[0]["displayName"] as? String, "A")
        XCTAssertEqual(models[1]["displayName"] as? String, "B")
    }
}
