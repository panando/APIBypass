import Foundation
import SwiftUI
import CodexRouterCore

/// Service managing the Codex Adaptor proxy server lifecycle.
@MainActor
final class CodexAdaptorService: ObservableObject {
    @Published var isRunning = false
    @Published var port: Int = 15721
    @Published var cdpConnectionState: CDPConnectionState = .disconnected

    private var server: CodexProxyServer?
    private var injector: CodexAppInjector?
    private var cdpStatePollingTask: Task<Void, Never>?

    init() {
        Task {
            let config = await CodexAdaptorConfigStore.shared.load()
            port = config.port
        }
    }

    func start() async throws {
        guard !isRunning else { return }

        let config = await CodexAdaptorConfigStore.shared.load()
        port = config.port

        // Sync config to ~/.codex/ files
        try await syncCodexConfig(config: config)

        let server = CodexProxyServer()
        self.server = server

        // Start CDP injector if enhancements enabled
        if config.cdpSettings.enhancementsEnabled {
            var cdpSettings = config.cdpSettings
            cdpSettings.proxyPort = config.port
            let inj = CodexAppInjector(
                debugPort: config.cdpDebugPort,
                settings: cdpSettings,
                logger: CodexLogStore.shared
            )
            self.injector = inj
            await inj.start()
            startCDPStatePolling()
        }

        try await server.start(port: config.port) { [weak self] in
            await self?.handleSettingsGet() ?? (200, "application/json", "{}")
        }

        isRunning = true
        CodexLogStore.shared.info("[CodexAdaptor] Service started on port \(config.port)")
    }

    /// Poll CDP connection state from the injector actor every 3 seconds.
    private func startCDPStatePolling() {
        cdpStatePollingTask?.cancel()
        cdpStatePollingTask = Task { [weak self] in
            while let strongSelf = self, !Task.isCancelled {
                if let inj = strongSelf.injector {
                    let state = await inj.snapshotState()
                    if Task.isCancelled { break }
                    strongSelf.cdpConnectionState = state
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stop() async {
        cdpStatePollingTask?.cancel()
        cdpStatePollingTask = nil

        await injector?.stop()
        injector = nil
        cdpConnectionState = .disconnected

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
            var cdpSettings = config.cdpSettings
            cdpSettings.proxyPort = config.port
            await inj.updateSettings(cdpSettings)
        }

        port = config.port
    }

    func pushInjectionSettings() async {
        guard let inj = injector else { return }
        let config = await CodexAdaptorConfigStore.shared.load()
        var cdpSettings = config.cdpSettings
        cdpSettings.proxyPort = port
        cdpSettings.modelProvider = (try? CodexConfigService.shared.getCurrentUpstreamProvider()?.id) ?? ""
        await inj.updateSettings(cdpSettings)
    }

    func currentInjectionSettings() async -> CDPInjectionSettings {
        let config = await CodexAdaptorConfigStore.shared.load()
        var settings = config.cdpSettings
        settings.modelProvider = (try? CodexConfigService.shared.getCurrentUpstreamProvider()?.id) ?? ""
        return settings
    }

    func handleSettingsGet() async -> (Int, String, String) {
        var settings = await currentInjectionSettings()
        settings.modelProvider = (try? CodexConfigService.shared.getCurrentUpstreamProvider()?.id) ?? ""
        settings.proxyPort = port
        let jsonData = (try? JSONEncoder().encode(settings)) ?? Data()
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            return (500, "application/json", #"{"error":"encode failed"}"#)
        }
        return (200, "application/json", jsonString)
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
        let mappings = await ConfigDataStore.shared.getMappings()
        let providers = await ConfigDataStore.shared.getProviders()
        let entries = CodexConfigBridge.buildCatalogEntries(
            customModels: config.currentCustomModels,
            mappings: mappings,
            providers: providers,
            wireAPI: config.wireAPI
        )
        guard !entries.isEmpty else { return nil }
        return ModelCatalog(models: entries)
    }
}
