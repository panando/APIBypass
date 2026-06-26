import Foundation
import TOMLKit
import CodexRouterCore

/// Service for managing Codex configuration.
/// Follows EchoBird's pattern exactly:
///   config.toml  — Codex-native fields only (base_url→proxy, wire_api, model_provider, model, bearer_token)
///   providers.json — proxy-internal metadata (upstream URL, reasoning config, model catalog)
///
/// All config.toml operations use TOMLKit for proper parse→modify→serialize round-trips,
/// guaranteeing that plugin/mcp/tool sections added by Codex or third-party tools are never
/// corrupted or stripped.
class CodexConfigService {
    static let shared = CodexConfigService()

    private let home: String
    private let configPath: String
    private let providersPath: String
    private let modelsCachePath: String
    private let backupSuffix = ".bak.codexadaptor"

    private static let templateSlug = "gpt-5.5"

    private convenience init() {
        self.init(home: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    init(home: String) {
        self.home = home
        self.configPath = "\(home)/.codex/config.toml"
        self.providersPath = "\(home)/.codex/providers.json"
        self.modelsCachePath = "\(home)/.codex/models_cache.json"
    }

    private func modelCatalogPath(for providerId: String) -> String {
        "\(home)/.codex/\(providerId)-model-catalog.json"
    }

    var configExists: Bool {
        FileManager.default.fileExists(atPath: configPath)
    }

    // MARK: - TOML Parsing

    /// Parse config.toml into a TOMLTable. Returns nil if file doesn't exist.
    private func parseConfig() throws -> TOMLTable? {
        guard FileManager.default.fileExists(atPath: configPath) else { return nil }
        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        return try TOMLTable(string: content)
    }

    /// Parse or create default config.
    private func parseOrCreateConfig() throws -> TOMLTable {
        if let table = try parseConfig() { return table }
        return try TOMLTable(string: defaultConfigTOML())
    }

    /// Serialize a TOMLTable back to TOML text and write to config.toml.
    /// Always backs up the existing file first.
    private func writeConfig(_ table: TOMLTable) throws {
        let toml = table.convert(to: .toml)

        // Backup first
        if FileManager.default.fileExists(atPath: configPath) {
            let backupPath = configPath + backupSuffix
            let existing = try String(contentsOfFile: configPath, encoding: .utf8)
            try existing.write(toFile: backupPath, atomically: true, encoding: .utf8)
        }

        let dir = (configPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try toml.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Providers JSON (proxy-internal data)

    private func readProviderStore() -> ProviderStore {
        guard FileManager.default.fileExists(atPath: providersPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: providersPath)),
              let store = try? JSONDecoder().decode(ProviderStore.self, from: data) else {
            return ProviderStore()
        }
        return store
    }

    private func writeProviderStore(_ store: ProviderStore) throws {
        let directory = (providersPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(store)
        try data.write(to: URL(fileURLWithPath: providersPath))
    }

    // MARK: - Reading Upstream Provider (for proxy)

    /// Get current upstream provider config from config.toml + providers.json.
    func getCurrentUpstreamProvider() throws -> UpstreamProvider? {
        guard let table = try parseConfig() else { return nil }
        guard let providerId = table["model_provider"]?.string else { return nil }

        let store = readProviderStore()
        guard let meta = store.providers[providerId],
              let upstreamURL = meta.upstreamBaseURL else { return nil }

        let providerTable = table["model_providers"]?.table?[providerId]?.table
        let name = providerTable?["name"]?.string ?? providerId
        let bearerToken = providerTable?["experimental_bearer_token"]?.string
        let usesChatCompletions = (meta.upstreamWireAPI ?? "chat").lowercased() == "chat"

        // Read modelCatalog from file (single source of truth)
        let modelCatalog = try? readModelCatalog(for: providerId)

        return UpstreamProvider(
            id: providerId,
            name: name,
            baseURL: upstreamURL,
            usesChatCompletions: usesChatCompletions,
            bearerToken: bearerToken,
            reasoningConfig: meta.reasoningConfig,
            modelCatalog: modelCatalog
        )
    }

    // MARK: - Reading Providers (for UI)

    /// Get all model providers from config.toml + providers.json.
    func getModelProviders() throws -> [CodexModelProvider] {
        guard let table = try parseConfig() else { return [] }

        let modelProviders = table["model_providers"]?.table ?? [:]
        let store = readProviderStore()
        var providers: [CodexModelProvider] = []

        for (providerId, value) in modelProviders {
            guard let section = value.table else { continue }
            let meta = store.providers[providerId]
            let name = section["name"]?.string ?? providerId
            let bearerToken = section["experimental_bearer_token"]?.string

            let modelCatalog = try? readModelCatalog(for: providerId)

            providers.append(CodexModelProvider(
                id: providerId,
                name: name,
                baseURL: meta?.upstreamBaseURL ?? section["base_url"]?.string ?? "",
                upstreamWireAPI: meta?.upstreamWireAPI ?? "chat",
                bearerToken: bearerToken,
                modelCatalog: modelCatalog,
                reasoningConfig: meta?.reasoningConfig,
                enabled: meta?.enabled ?? true
            ))
        }

        return providers
    }

    func getCurrentProvider() throws -> CodexModelProvider? {
        guard let table = try parseConfig() else { return nil }
        guard let providerId = table["model_provider"]?.string else { return nil }
        return try getModelProviders().first { $0.id == providerId }
    }

    func getCurrentModel() throws -> String? {
        guard let table = try parseConfig() else { return nil }
        return table["model"]?.string
    }

    /// Read model catalog from JSON file.
    func readModelCatalog(for providerId: String? = nil) throws -> ModelCatalog? {
        let path: String
        if let providerId = providerId {
            path = modelCatalogPath(for: providerId)
        } else {
            guard let table = try parseConfig(),
                  let catalogFile = table["model_catalog_json"]?.string else { return nil }
            path = "\(home)/.codex/\(catalogFile)"
        }

        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return nil }

        let entries: [ModelCatalogEntry] = models.compactMap { model in
            guard let slug = model["slug"] as? String else { return nil }
            return ModelCatalogEntry(
                model: slug,
                displayName: model["display_name"] as? String,
                contextWindow: model["context_window"] as? UInt64
            )
        }
        return ModelCatalog(models: entries)
    }

    // MARK: - Writing Codex Config

    /// Switch active provider (and optionally model) in config.toml.
    /// Matches EchoBird's apply_codex: always ensures model_reasoning_effort and disable_response_storage are set.
    func switchProvider(to providerId: String, model: String? = nil) throws {
        let table = try parseOrCreateConfig()
        table["model_provider"] = providerId
        table["model_reasoning_effort"] = "medium"
        table["disable_response_storage"] = true
        if let model = model {
            table["model"] = model
        }
        try writeConfig(table)
    }

    /// Save a provider: config.toml gets Codex-native fields, providers.json gets proxy metadata.
    func saveProvider(_ provider: CodexModelProvider) throws {
        // 1. Write Codex-native section to config.toml
        let table = try parseOrCreateConfig()

        // Build provider section — matches EchoBird's canonical config.toml
        let providerSection = TOMLTable()
        providerSection["name"] = provider.name
        providerSection["base_url"] = "http://127.0.0.1:15721/v1"
        providerSection["wire_api"] = "responses"
        providerSection["requires_openai_auth"] = true
        if let token = provider.bearerToken, !token.isEmpty {
            providerSection["experimental_bearer_token"] = token
        }

        // Get or create model_providers table
        let modelProviders = table["model_providers"]?.table ?? TOMLTable()
        modelProviders[provider.id] = providerSection
        table["model_providers"] = modelProviders

        // Top-level fields matching EchoBird's apply_codex
        table["model_reasoning_effort"] = "medium"
        table["disable_response_storage"] = true

        // Model catalog field
        if let catalog = provider.modelCatalog, !catalog.models.isEmpty {
            try generateModelCatalogJSON(from: catalog, providerId: provider.id)
            table["model_catalog_json"] = "\(provider.id)-model-catalog.json"
            // Always ensure model is set to a value present in the catalog.
            // If the current model isn't in the new catalog, switch to the first entry.
            let currentModel = table["model"]?.string
            let modelSlugs = catalog.models.map { $0.model }
            if currentModel == nil || !modelSlugs.contains(currentModel!) {
                table["model"] = modelSlugs[0]
            }
        } else {
            // Only remove if it's for this provider
            if let existing = table["model_catalog_json"]?.string, existing.hasPrefix(provider.id) {
                table.remove(at: "model_catalog_json")
            }
        }

        try writeConfig(table)

        // 2. Write proxy metadata to providers.json (no modelCatalog - read from file instead)
        var store = readProviderStore()
        store.providers[provider.id] = ProviderMetaEntry(
            upstreamBaseURL: provider.baseURL.isEmpty ? nil : provider.baseURL,
            upstreamWireAPI: provider.upstreamWireAPI.isEmpty ? "chat" : provider.upstreamWireAPI,
            reasoningConfig: provider.reasoningConfig
        )
        try writeProviderStore(store)
    }

    /// Toggle enabled state of a provider in providers.json.
    func setProviderEnabled(id: String, enabled: Bool) throws {
        var store = readProviderStore()
        store.providers[id]?.enabled = enabled
        try writeProviderStore(store)
    }

    /// Delete a provider from config.toml and providers.json.
    func deleteProvider(id: String) throws {
        let table = try parseOrCreateConfig()

        // If deleting current provider, switch to another or clear
        if table["model_provider"]?.string == id {
            let modelProviders = table["model_providers"]?.table ?? [:]
            let otherIds = modelProviders.keys.filter { $0 != id }
            if let first = otherIds.first {
                table["model_provider"] = first
                // Try to also switch model
                if let catalog = try? readModelCatalog(for: first),
                   let firstModel = catalog.models.first?.model {
                    table["model"] = firstModel
                }
            } else {
                table.remove(at: "model_provider")
            }
        }

        // Remove provider section from model_providers table
        if let modelProviders = table["model_providers"]?.table {
            modelProviders.remove(at: id)
        }

        // Clean up model_catalog_json if it belongs to this provider
        if let catalogJson = table["model_catalog_json"]?.string, catalogJson.hasPrefix(id) {
            table.remove(at: "model_catalog_json")
        }

        try writeConfig(table)

        // Remove from providers.json
        var store = readProviderStore()
        store.providers.removeValue(forKey: id)
        try writeProviderStore(store)

        // Remove model catalog file
        let catalogPath = modelCatalogPath(for: id)
        if FileManager.default.fileExists(atPath: catalogPath) {
            try? FileManager.default.removeItem(atPath: catalogPath)
        }
    }

    /// Restore config.toml from last backup.
    func restoreOriginalConfig() throws {
        let backupPath = configPath + backupSuffix
        guard FileManager.default.fileExists(atPath: backupPath) else {
            throw CodexConfigError.backupNotFound
        }
        let original = try String(contentsOfFile: backupPath, encoding: .utf8)
        try original.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Model Catalog Generation

    private func generateModelCatalogJSON(from catalog: ModelCatalog, providerId: String) throws {
        guard let template = try loadModelCatalogTemplate() else {
            throw CodexConfigError.parseError("Failed to load gpt-5.5 template for model catalog")
        }

        let defaultContextWindow: UInt64 = 128000

        let entries = catalog.models.enumerated().map { (index, entry) -> [String: Any] in
            let displayName = entry.displayName ?? entry.model
            let contextWindow = entry.contextWindow ?? defaultContextWindow
            return generateModelCatalogEntry(
                from: template,
                model: entry.model,
                displayName: displayName,
                contextWindow: contextWindow,
                priority: index
            )
        }

        let catalogJSON: [String: Any] = ["models": entries]
        let jsonData = try JSONSerialization.data(withJSONObject: catalogJSON, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: URL(fileURLWithPath: modelCatalogPath(for: providerId)))
    }

    private func generateModelCatalogEntry(
        from template: [String: Any],
        model: String,
        displayName: String,
        contextWindow: UInt64,
        priority: Int
    ) -> [String: Any] {
        var entry = template
        entry["slug"] = model
        entry["display_name"] = displayName
        entry["description"] = displayName
        entry["context_window"] = contextWindow
        entry["max_context_window"] = contextWindow
        entry["priority"] = 1000 + priority
        entry["additional_speed_tiers"] = [] as [String]
        entry["service_tiers"] = [] as [String]
        entry["availability_nux"] = NSNull()
        entry["upgrade"] = NSNull()
        return entry
    }

    // MARK: - Template Loading

    private func loadModelCatalogTemplate() throws -> [String: Any]? {
        if let template = try loadTemplateFromModelsCache() { return template }
        if let template = loadTemplateFromCodexCLI() { return template }
        return staticTemplateFallback()
    }

    private func loadTemplateFromModelsCache() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: modelsCachePath) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: modelsCachePath))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return nil }
        return models.first { ($0["slug"] as? String) == Self.templateSlug }
    }

    private func loadTemplateFromCodexCLI() -> [String: Any]? {
        for candidate in codexCLICandidates() {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: candidate)
            process.arguments = ["debug", "models", "--bundled"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                // Read pipe data BEFORE waitUntilExit to avoid deadlock when output exceeds pipe buffer (~64KB)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { continue }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["models"] as? [[String: Any]] else { continue }
                if let found = models.first(where: { ($0["slug"] as? String) == Self.templateSlug }) {
                    return found
                }
            } catch { continue }
        }
        return nil
    }

    private func codexCLICandidates() -> [String] {
        var candidates = ["codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        for dir in [".nvm/current/bin", ".volta/bin", ".asdf/shims", ".local/bin"] {
            candidates.append("\(home)/\(dir)/codex")
        }
        return candidates
    }

    private func staticTemplateFallback() -> [String: Any] {
        return [
            "default_reasoning_level": "medium",
            "supported_reasoning_levels": [
                ["effort": "low", "description": "Fast responses with lighter reasoning"],
                ["effort": "medium", "description": "Balances speed and reasoning depth for everyday tasks"],
                ["effort": "high", "description": "Greater reasoning depth for complex problems"]
            ],
            "shell_type": "shell_command",
            "visibility": "list",
            "supported_in_api": true,
            "additional_speed_tiers": [] as [String],
            "service_tiers": [] as [String],
            "availability_nux": NSNull(),
            "upgrade": NSNull(),
            "base_instructions": "You are Codex, a coding agent.",
            "model_messages": [
                "instructions_template": "You are Codex, a coding agent. {{ personality }}",
                "instructions_variables": [
                    "personality_default": "",
                    "personality_friendly": "You are helpful and friendly.\n",
                    "personality_pragmatic": "You are a deeply pragmatic software engineer.\n"
                ]
            ] as [String: Any],
            "supports_reasoning_summaries": true,
            "default_reasoning_summary": "none",
            "support_verbosity": true,
            "default_verbosity": "low",
            "apply_patch_tool_type": "freeform",
            "web_search_tool_type": "text_and_image",
            "truncation_policy": ["mode": "tokens", "limit": 10000] as [String: Any],
            "supports_parallel_tool_calls": true,
            "supports_image_detail_original": true,
            "effective_context_window_percent": 95,
            "experimental_supported_tools": [] as [String],
            "input_modalities": ["text", "image"],
            "supports_search_tool": true
        ]
    }

    /// Default minimal config.toml for new setups.
    private func defaultConfigTOML() -> String {
        return """
        model_provider = "custom"

        """
    }
}

// MARK: - Providers JSON Model

/// Root of ~/.codex/providers.json
struct ProviderStore: Codable {
    var providers: [String: ProviderMetaEntry] = [:]
}

/// Proxy-internal metadata for a provider. Mirrors EchoBird's ~/.echobird/codex.json pattern.
/// Note: modelCatalog is NOT stored here - it lives in {providerId}-model-catalog.json files.
struct ProviderMetaEntry: Codable {
    var upstreamBaseURL: String?
    var upstreamWireAPI: String?
    var reasoningConfig: ReasoningConfig?
    var enabled: Bool?
}

// MARK: - Public Types

/// Codex model provider configuration (for UI).
struct CodexModelProvider: Identifiable, Equatable {
    let id: String
    var name: String
    var baseURL: String
    var upstreamWireAPI: String
    var bearerToken: String?
    var modelCatalog: ModelCatalog?
    var reasoningConfig: ReasoningConfig?
    var enabled: Bool

    init(
        id: String,
        name: String,
        baseURL: String,
        upstreamWireAPI: String = "chat",
        bearerToken: String? = nil,
        modelCatalog: ModelCatalog? = nil,
        reasoningConfig: ReasoningConfig? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.upstreamWireAPI = upstreamWireAPI
        self.bearerToken = bearerToken
        self.modelCatalog = modelCatalog
        self.reasoningConfig = reasoningConfig
        self.enabled = enabled
    }

    static func == (lhs: CodexModelProvider, rhs: CodexModelProvider) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.baseURL == rhs.baseURL &&
        lhs.upstreamWireAPI == rhs.upstreamWireAPI &&
        lhs.bearerToken == rhs.bearerToken &&
        lhs.modelCatalog == rhs.modelCatalog &&
        lhs.reasoningConfig == rhs.reasoningConfig &&
        lhs.enabled == rhs.enabled
    }
}

enum CodexConfigError: Error, LocalizedError {
    case configNotFound
    case backupNotFound
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .configNotFound: return "Codex config file not found"
        case .backupNotFound: return "Backup config file not found"
        case .parseError(let message): return "Failed to parse config: \(message)"
        }
    }
}

/// Upstream provider configuration for RequestHandler.
struct UpstreamProvider: Sendable {
    let id: String
    let name: String
    let baseURL: String
    let usesChatCompletions: Bool
    let bearerToken: String?
    let reasoningConfig: ReasoningConfig?
    let modelCatalog: ModelCatalog?

    init(
        id: String,
        name: String,
        baseURL: String,
        usesChatCompletions: Bool,
        bearerToken: String? = nil,
        reasoningConfig: ReasoningConfig? = nil,
        modelCatalog: ModelCatalog? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.usesChatCompletions = usesChatCompletions
        self.bearerToken = bearerToken
        self.reasoningConfig = reasoningConfig
        self.modelCatalog = modelCatalog
    }
}
