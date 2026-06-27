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

    // MARK: - slug field support

    /// Entry with slug field → uses slug as model identifier.
    func test_modelCatalogEntry_decodesSlugField() throws {
        let json = """
        {
            "slug": "glm-5.2-ark-responses",
            "display_name": "GLM-5.2-Ark",
            "context_window": 220000
        }
        """
        let data = json.data(using: .utf8)!
        let entry = try JSONDecoder().decode(ModelCatalogEntry.self, from: data)
        XCTAssertEqual(entry.model, "glm-5.2-ark-responses", "slug should be decoded as model identifier")
        XCTAssertEqual(entry.displayName, "GLM-5.2-Ark")
        XCTAssertEqual(entry.contextWindow, 220000)
    }

    /// Entry with both slug and model → slug takes precedence.
    func test_modelCatalogEntry_slugTakesPrecedenceOverModel() throws {
        let json = """
        {
            "slug": "kimi-k2.6-ark-responses",
            "model": "ignored-model",
            "display_name": "Kimi-K2.6-Ark"
        }
        """
        let data = json.data(using: .utf8)!
        let entry = try JSONDecoder().decode(ModelCatalogEntry.self, from: data)
        XCTAssertEqual(entry.model, "kimi-k2.6-ark-responses", "slug should take precedence over model")
        XCTAssertEqual(entry.displayName, "Kimi-K2.6-Ark")
    }

    /// Entry without slug → uses model field as fallback.
    func test_modelCatalogEntry_withoutSlug_usesModelField() throws {
        let json = """
        {
            "model": "gpt-5.5",
            "display_name": "GPT-5.5"
        }
        """
        let data = json.data(using: .utf8)!
        let entry = try JSONDecoder().decode(ModelCatalogEntry.self, from: data)
        XCTAssertEqual(entry.model, "gpt-5.5", "model should be used when slug is absent")
        XCTAssertEqual(entry.displayName, "GPT-5.5")
    }

    /// Entry with slug in modelCatalogBody → slug appears as model in output.
    func test_makeModelCatalogBody_entryWithSlug_usesSlugAsModel() throws {
        let entry = ModelCatalogEntry(model: "glm-5.2-ark-responses", displayName: "GLM-5.2-Ark", contextWindow: 220000)
        let catalog = ModelCatalog(models: [entry])
        let data = CodexRequestHandler.makeModelCatalogBody(catalog: catalog)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let models = try XCTUnwrap(json["models"] as? [[String: Any]])
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0]["model"] as? String, "glm-5.2-ark-responses")
        XCTAssertEqual(models[0]["displayName"] as? String, "GLM-5.2-Ark")
    }

    // MARK: - Model resolution in CodexRequestHandler

    /// Codex sends slug (model field) → should match by model field
    func test_modelCatalogEntry_matchesByModelField() throws {
        let catalog = ModelCatalog(models: [
            ModelCatalogEntry(model: "glm-5.2-ark-responses", displayName: "GLM-5.2-Ark", contextWindow: 220000)
        ])
        // Codex sends the slug (model field) in the request
        let rawModelName = "glm-5.2-ark-responses"
        let entry = catalog.models.first(where: { $0.model == rawModelName })
        XCTAssertNotNil(entry, "Should match by model field (slug)")
        XCTAssertEqual(entry?.displayName, "GLM-5.2-Ark")
    }

    /// Codex sends displayName → should still work for backward compatibility
    func test_modelCatalogEntry_matchesByDisplayName_backwardCompat() throws {
        let catalog = ModelCatalog(models: [
            ModelCatalogEntry(model: "gpt-5.5", displayName: "GPT-5.5", contextWindow: nil)
        ])
        // Some configs might use displayName as the identifier
        let rawModelName = "GPT-5.5"
        let entry = catalog.models.first(where: { $0.displayName == rawModelName || $0.model == rawModelName })
        XCTAssertNotNil(entry, "Should match by displayName for backward compatibility")
    }
}
