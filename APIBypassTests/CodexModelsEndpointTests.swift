import XCTest
import CodexRouterCore
@testable import APIBypass

final class CodexModelsEndpointTests: XCTestCase {

    /// Nil catalog (no provider, or provider with no configured models) → empty list, HTTP 200 shape.
    func test_makeModelsListBody_nilCatalog_returnsEmptyList() throws {
        let data = CodexRequestHandler.makeModelsListBody(catalog: nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["object"] as? String, "list")
        XCTAssertEqual((json["data"] as? [Any])?.count, 0)
    }

    /// Catalog with one entry using displayName → id is the displayName (alias).
    func test_makeModelsListBody_entryWithDisplayName_usesDisplayNameAsId() throws {
        let catalog = ModelCatalog(models: [
            ModelCatalogEntry(model: "gpt-5.5", displayName: "My Alias", contextWindow: 128000)
        ])
        let data = CodexRequestHandler.makeModelsListBody(catalog: catalog)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let modelsArray = try XCTUnwrap(json["data"] as? [[String: Any]])
        XCTAssertEqual(modelsArray.count, 1)
        let entry = modelsArray[0]
        XCTAssertEqual(entry["id"] as? String, "My Alias")
        XCTAssertEqual(entry["object"] as? String, "model")
        XCTAssertEqual(entry["owned_by"] as? String, "apibypass")
    }

    /// Catalog with one entry, no displayName → id falls back to model slug.
    func test_makeModelsListBody_entryWithoutDisplayName_usesModelSlugAsId() throws {
        let catalog = ModelCatalog(models: [
            ModelCatalogEntry(model: "claude-sonnet-4-6", displayName: nil, contextWindow: nil)
        ])
        let data = CodexRequestHandler.makeModelsListBody(catalog: catalog)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entry = try XCTUnwrap((json["data"] as? [[String: Any]])?.first)
        XCTAssertEqual(entry["id"] as? String, "claude-sonnet-4-6")
    }

    /// Multiple entries preserve order.
    func test_makeModelsListBody_multipleEntries_preservesOrder() throws {
        let catalog = ModelCatalog(models: [
            ModelCatalogEntry(model: "model-a", displayName: "A", contextWindow: nil),
            ModelCatalogEntry(model: "model-b", displayName: "B", contextWindow: nil)
        ])
        let data = CodexRequestHandler.makeModelsListBody(catalog: catalog)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let ids = (json["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
        XCTAssertEqual(ids, ["A", "B"])
    }

    /// Empty catalog (models: []) → empty list, same as nil.
    func test_makeModelsListBody_emptyCatalog_returnsEmptyList() throws {
        let catalog = ModelCatalog(models: [])
        let data = CodexRequestHandler.makeModelsListBody(catalog: catalog)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["data"] as? [Any])?.count, 0)
    }
}
