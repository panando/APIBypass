import XCTest
import CodexRouterCore

/// Tests for CDPInjectionSettings Codable behavior.
///
/// These tests verify that removing `codexAppPluginEntryUnlock` from the settings
/// does not break backward compatibility or affect other functionality.
final class CDPInjectionSettingsTests: XCTestCase {

    // MARK: - Codable Backward Compatibility

    /// Verifies that JSON without `codexAppPluginEntryUnlock` can be decoded.
    /// This is critical for forward compatibility when the field is removed.
    func test_decode_succeedsWithoutPluginEntryUnlockField() throws {
        let json = """
        {
            "codexAppForcePluginInstall": true,
            "enhancementsEnabled": true,
            "launchMode": "patch",
            "codexAppVersion": "1.0.0",
            "codexAppPluginMarketplaceUnlock": true,
            "codexAppModelWhitelistUnlock": true,
            "modelProvider": "test",
            "proxyPort": 15721
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(CDPInjectionSettings.self, from: json)

        XCTAssertTrue(settings.codexAppForcePluginInstall)
        XCTAssertTrue(settings.enhancementsEnabled)
        XCTAssertEqual(settings.launchMode, "patch")
        XCTAssertTrue(settings.codexAppPluginMarketplaceUnlock)
        XCTAssertTrue(settings.codexAppModelWhitelistUnlock)
    }

    /// Verifies that JSON with `codexAppPluginEntryUnlock: false` is decoded correctly.
    /// After removal, this field should be ignored (or use default).
    func test_decode_ignoresPluginEntryUnlockWhenFalse() throws {
        let json = """
        {
            "codexAppPluginEntryUnlock": false,
            "codexAppForcePluginInstall": true,
            "enhancementsEnabled": true,
            "launchMode": "patch",
            "codexAppVersion": "",
            "codexAppPluginMarketplaceUnlock": true,
            "codexAppModelWhitelistUnlock": true,
            "modelProvider": "",
            "proxyPort": 15721
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(CDPInjectionSettings.self, from: json)

        XCTAssertTrue(settings.codexAppForcePluginInstall)
        XCTAssertTrue(settings.enhancementsEnabled)
    }

    /// Verifies that JSON with `codexAppPluginEntryUnlock: true` is decoded correctly.
    /// After removal, this field should be ignored (or use default).
    func test_decode_ignoresPluginEntryUnlockWhenTrue() throws {
        let json = """
        {
            "codexAppPluginEntryUnlock": true,
            "codexAppForcePluginInstall": false,
            "enhancementsEnabled": true,
            "launchMode": "relay",
            "codexAppVersion": "",
            "codexAppPluginMarketplaceUnlock": false,
            "codexAppModelWhitelistUnlock": false,
            "modelProvider": "",
            "proxyPort": 15721
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(CDPInjectionSettings.self, from: json)

        XCTAssertFalse(settings.codexAppForcePluginInstall)
        XCTAssertEqual(settings.launchMode, "relay")
        XCTAssertFalse(settings.codexAppPluginMarketplaceUnlock)
    }

    // MARK: - Default Values

    /// Verifies default values are sensible when fields are missing.
    func test_defaultValues() {
        let settings = CDPInjectionSettings()

        // After removal, pluginEntryUnlock should either not exist or have a sensible default
        XCTAssertTrue(settings.codexAppForcePluginInstall)
        XCTAssertTrue(settings.enhancementsEnabled)
        XCTAssertEqual(settings.launchMode, "patch")
        XCTAssertTrue(settings.codexAppPluginMarketplaceUnlock)
        XCTAssertTrue(settings.codexAppModelWhitelistUnlock)
    }

    // MARK: - Encoding

    /// Verifies that encoding and decoding round-trips correctly.
    func test_encodeDecode_roundTrip() throws {
        let original = CDPInjectionSettings(
            codexAppForcePluginInstall: false,
            enhancementsEnabled: false,
            launchMode: "relay",
            codexAppVersion: "1.2.3",
            codexAppPluginMarketplaceUnlock: false,
            codexAppModelWhitelistUnlock: false,
            modelProvider: "custom",
            proxyPort: 8080
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CDPInjectionSettings.self, from: data)

        XCTAssertEqual(decoded.codexAppForcePluginInstall, original.codexAppForcePluginInstall)
        XCTAssertEqual(decoded.enhancementsEnabled, original.enhancementsEnabled)
        XCTAssertEqual(decoded.launchMode, original.launchMode)
        XCTAssertEqual(decoded.codexAppVersion, original.codexAppVersion)
        XCTAssertEqual(decoded.codexAppPluginMarketplaceUnlock, original.codexAppPluginMarketplaceUnlock)
        XCTAssertEqual(decoded.codexAppModelWhitelistUnlock, original.codexAppModelWhitelistUnlock)
        XCTAssertEqual(decoded.modelProvider, original.modelProvider)
        XCTAssertEqual(decoded.proxyPort, original.proxyPort)
    }

    // MARK: - Independence from pluginEntryUnlock

    /// Verifies that forcePluginInstall can be enabled independently.
    func test_forcePluginInstall_independentFromPluginEntryUnlock() throws {
        // JSON with forcePluginInstall=true but NO pluginEntryUnlock field
        let json = """
        {
            "codexAppForcePluginInstall": true,
            "enhancementsEnabled": true,
            "launchMode": "patch",
            "codexAppVersion": "",
            "codexAppPluginMarketplaceUnlock": false,
            "codexAppModelWhitelistUnlock": false,
            "modelProvider": "",
            "proxyPort": 15721
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(CDPInjectionSettings.self, from: json)

        XCTAssertTrue(settings.codexAppForcePluginInstall, "forcePluginInstall should be true regardless of pluginEntryUnlock")
    }

    /// Verifies that pluginMarketplaceUnlock can be enabled independently.
    func test_pluginMarketplaceUnlock_independentFromPluginEntryUnlock() throws {
        // JSON with pluginMarketplaceUnlock=true but NO pluginEntryUnlock field
        let json = """
        {
            "codexAppForcePluginInstall": false,
            "enhancementsEnabled": true,
            "launchMode": "patch",
            "codexAppVersion": "",
            "codexAppPluginMarketplaceUnlock": true,
            "codexAppModelWhitelistUnlock": false,
            "modelProvider": "",
            "proxyPort": 15721
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(CDPInjectionSettings.self, from: json)

        XCTAssertTrue(settings.codexAppPluginMarketplaceUnlock, "pluginMarketplaceUnlock should be true regardless of pluginEntryUnlock")
    }

    /// Verifies that modelWhitelistUnlock can be enabled independently.
    func test_modelWhitelistUnlock_independentFromPluginEntryUnlock() throws {
        // JSON with modelWhitelistUnlock=true but NO pluginEntryUnlock field
        let json = """
        {
            "codexAppForcePluginInstall": false,
            "enhancementsEnabled": true,
            "launchMode": "patch",
            "codexAppVersion": "",
            "codexAppPluginMarketplaceUnlock": false,
            "codexAppModelWhitelistUnlock": true,
            "modelProvider": "",
            "proxyPort": 15721
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(CDPInjectionSettings.self, from: json)

        XCTAssertTrue(settings.codexAppModelWhitelistUnlock, "modelWhitelistUnlock should be true regardless of pluginEntryUnlock")
    }
}
