import Foundation
import SwiftUI
import CodexRouterCore

/// Service managing the Codex Adaptor proxy server lifecycle.
@MainActor
final class CodexAdaptorService: ObservableObject {
    @Published var isRunning = false
    @Published var port: Int = 15721

    private var server: CodexProxyServer?
    private var injector: CodexAppInjector?

    init() {
        Task {
            let config = await CodexAdaptorConfigStore.shared.load()
            port = config.port
        }
    }

    func start() async throws {
        let config = await CodexAdaptorConfigStore.shared.load()
        port = config.port

        // Sync config to ~/.codex/ files
        try await syncCodexConfig(config: config)

        let server = CodexProxyServer()
        self.server = server

        // Start CDP injector if enhancements enabled
        if config.cdpSettings.enhancementsEnabled {
            let inj = CodexAppInjector(
                debugPort: config.cdpDebugPort,
                settings: config.cdpSettings
            )
            self.injector = inj
            await inj.start()
        }

        try await server.start(port: config.port) { [weak self] in
            await self?.handleSettingsGet() ?? (200, "application/json", "{}")
        }

        isRunning = true
        CodexLogStore.shared.info("[CodexAdaptor] Service started on port \(config.port)")
    }

    func stop() async {
        await injector?.stop()
        injector = nil

        await server?.stop()
        server = nil

        isRunning = false
        CodexLogStore.shared.info("[CodexAdaptor] Service stopped")
    }

    func updateConfig(_ config: CodexAdaptorConfig) async throws {
        await CodexAdaptorConfigStore.shared.save(config)
        try await syncCodexConfig(config: config)

        // Update CDP settings if running
        if let inj = injector {
            await inj.updateSettings(config.cdpSettings)
        }

        port = config.port
    }

    func pushInjectionSettings() async {
        guard let inj = injector else { return }
        let config = await CodexAdaptorConfigStore.shared.load()
        await inj.updateSettings(config.cdpSettings)
    }

    func currentInjectionSettings() async -> CDPInjectionSettings {
        let config = await CodexAdaptorConfigStore.shared.load()
        return config.cdpSettings
    }

    func handleSettingsGet() async -> (Int, String, String) {
        if let inj = injector {
            return await inj.handleSettingsGet()
        }
        return (200, "application/json", "{}")
    }

    /// Sync APIBypass Codex Adaptor config to ~/.codex/ files for Codex CLI compatibility.
    /// The proxy forwards requests to the APIBypass HTTP server (the sole upstream provider).
    private func syncCodexConfig(config: CodexAdaptorConfig) async throws {
        let configService = CodexConfigService.shared

        // APIBypass server port (same logic as HTTPServer)
        let savedPort = UserDefaults.standard.integer(forKey: "serverPort")
        let apiBypassPort = savedPort > 0 ? savedPort : 8390

        // Build a CodexModelProvider pointing to the APIBypass server
        let provider = CodexModelProvider(
            id: "apibypass",
            name: "APIBypass",
            baseURL: "http://127.0.0.1:\(apiBypassPort)/v1",
            upstreamWireAPI: config.wireAPI.rawValue,
            bearerToken: nil,
            modelCatalog: await buildModelCatalog(from: config),
            reasoningConfig: config.reasoningOverrideEnabled ? config.reasoningConfig : nil,
            enabled: true
        )

        try configService.saveProvider(provider)
        try configService.switchProvider(to: "apibypass")
    }

    private func buildModelCatalog(from config: CodexAdaptorConfig) async -> ModelCatalog? {
        let customModels = config.currentCustomModels
        guard !customModels.isEmpty else { return nil }
        let mappings = await ConfigDataStore.shared.getMappings()
        let entries = customModels.compactMap { entry -> ModelCatalogEntry? in
            guard let mapping = mappings.first(where: { $0.id == entry.modelMappingId }) else {
                return nil
            }
            return ModelCatalogEntry(
                model: mapping.incomingModel,
                displayName: entry.alias.isEmpty ? mapping.incomingModel : entry.alias,
                contextWindow: entry.contextWindow
            )
        }
        guard !entries.isEmpty else { return nil }
        return ModelCatalog(models: entries)
    }
}
