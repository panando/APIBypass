import Foundation
import Combine

/// UI binding layer for configuration data
/// All data is synced from ConfigDataStore (actor) to ensure thread safety
@MainActor
final class ConfigManager: ObservableObject {
    @Published var mappings: [ModelMapping] = []
    @Published var providers: [ProviderConfig] = []

    private let store = ConfigDataStore.shared

    init() {
        Task {
            await refresh()
        }
    }

    /// Sync data from ConfigDataStore
    func refresh() async {
        mappings = await store.getMappings()
        providers = await store.getProviders()
    }

    // MARK: - Mapping CRUD

    func add(_ mapping: ModelMapping) async {
        await store.add(mapping)
        await refresh()
    }

    func update(_ mapping: ModelMapping) async {
        await store.update(mapping)
        await refresh()
    }

    func delete(_ id: UUID) async {
        await store.deleteMapping(id)
        await refresh()
    }

    func findMapping(for model: String) async -> ModelMapping? {
        await store.findMapping(for: model)
    }

    // MARK: - Provider CRUD

    func addProvider(_ provider: ProviderConfig) async {
        await store.addProvider(provider)
        await refresh()
    }

    func updateProvider(_ provider: ProviderConfig) async {
        await store.updateProvider(provider)
        await refresh()
    }

    func deleteProvider(_ id: UUID) async {
        await store.deleteProvider(id)
        await refresh()
    }

    func findProvider(for id: UUID) async -> ProviderConfig? {
        await store.findProvider(for: id)
    }

    func mappingsForProvider(_ providerId: UUID) async -> [ModelMapping] {
        await store.mappingsForProvider(providerId)
    }

    func isProviderValid(for mapping: ModelMapping) async -> Bool {
        await store.isProviderValid(for: mapping)
    }

    // MARK: - Reordering

    func moveProvider(from source: IndexSet, to destination: Int) async {
        await store.moveProvider(from: source, to: destination)
        await refresh()
    }

    func moveMapping(providerId: UUID, from source: IndexSet, to destination: Int) async {
        await store.moveMapping(providerId: providerId, from: source, to: destination)
        await refresh()
    }

    // MARK: - Synchronous Access (for UI bindings that can't use async)

    /// Synchronous accessor for mappings - returns cached value
    var cachedMappings: [ModelMapping] { mappings }
    var cachedProviders: [ProviderConfig] { providers }
}
