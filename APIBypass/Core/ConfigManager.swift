import Foundation
import Combine

final class ConfigManager: ObservableObject {
    @Published var mappings: [ModelMapping] = []
    @Published var providers: [ProviderConfig] = []

    private let defaultsKey: String
    private let providersDefaultsKey = "com.apibypass.providers"
    private let migratedKey = "com.apibypass.migratedToProviders"
    private let defaults = UserDefaults.standard

    init(defaultsKey: String = "com.apibypass.mappings") {
        self.defaultsKey = defaultsKey
        loadProviders()
        load()
        migrateIfNeeded()
        cleanupOrphanMappings()
        migrateProviderEnvironmentVariables()
    }

    // MARK: - Orphan Cleanup

    private func cleanupOrphanMappings() {
        let validIds = Set(providers.map { $0.id })
        let orphans = mappings.filter { !validIds.contains($0.providerConfigId) }
        if !orphans.isEmpty {
            mappings.removeAll { !validIds.contains($0.providerConfigId) }
            save()
            print("[Cleanup] Removed \(orphans.count) orphan mapping(s) with invalid provider")
        }
    }

    // MARK: - Environment Variables Migration

    private func migrateProviderEnvironmentVariables() {
        var needsSave = false

        for index in providers.indices {
            if providers[index].environmentVariables.isEmpty {
                providers[index].environmentVariables = ProviderConfig.defaultEnvironmentVariables()
                needsSave = true
            }
        }

        if needsSave {
            saveProviders()
            print("[Migration] Added default environment variables to \(providers.count) provider(s)")
        }
    }

    // MARK: - Mapping CRUD

    func add(_ mapping: ModelMapping) {
        mappings.append(mapping)
        save()
    }

    func update(_ mapping: ModelMapping) {
        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = mapping
            save()
        }
    }

    func delete(_ id: UUID) {
        mappings.removeAll { $0.id == id }
        save()
    }

    func findMapping(for model: String) -> ModelMapping? {
        mappings.first { $0.matches(model: model) }
    }

    // MARK: - Provider CRUD

    func addProvider(_ provider: ProviderConfig) {
        providers.append(provider)
        saveProviders()
    }

    func updateProvider(_ provider: ProviderConfig) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
            saveProviders()
        }
    }

    func deleteProvider(_ id: UUID) {
        providers.removeAll { $0.id == id }
        saveProviders()
    }

    func findProvider(for id: UUID) -> ProviderConfig? {
        providers.first { $0.id == id }
    }

    func mappingsForProvider(_ providerId: UUID) -> [ModelMapping] {
        mappings.filter { $0.providerConfigId == providerId }
    }

    func isProviderValid(for mapping: ModelMapping) -> Bool {
        providers.contains { $0.id == mapping.providerConfigId }
    }

    // MARK: - Reordering

    func moveProvider(from source: IndexSet, to destination: Int) {
        providers.move(fromOffsets: source, toOffset: destination)
        saveProviders()
    }

    func moveMapping(providerId: UUID, from source: IndexSet, to destination: Int) {
        let providerMappingIndices = mappings.enumerated()
            .filter { $0.element.providerConfigId == providerId }
            .map { $0.offset }

        guard !providerMappingIndices.isEmpty else { return }

        var globalSource = IndexSet()
        for localIndex in source {
            if localIndex < providerMappingIndices.count {
                globalSource.insert(providerMappingIndices[localIndex])
            }
        }

        let globalDestination: Int
        if destination < providerMappingIndices.count {
            globalDestination = providerMappingIndices[destination]
        } else {
            globalDestination = providerMappingIndices.last! + 1
        }

        mappings.move(fromOffsets: globalSource, toOffset: globalDestination)
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ModelMapping].self, from: data) else {
            mappings = []
            return
        }
        mappings = decoded
    }

    private func saveProviders() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        defaults.set(data, forKey: providersDefaultsKey)
    }

    private func loadProviders() {
        guard let data = defaults.data(forKey: providersDefaultsKey),
              let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: data) else {
            providers = []
            return
        }
        providers = decoded
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        guard !defaults.bool(forKey: migratedKey) else { return }

        guard let data = defaults.data(forKey: defaultsKey) else {
            defaults.set(true, forKey: migratedKey)
            return
        }

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            defaults.set(true, forKey: migratedKey)
            return
        }

        // Parse old mapping data that has apiProvider and baseURL fields
        struct OldMapping {
            let id: UUID
            let name: String
            let incomingModel: String
            let actualModel: String
            let apiProvider: APIProvider
            let baseURL: URL
            let parameters: InjectedParameters
            let isEnabled: Bool
        }

        var oldMappings: [OldMapping] = []

        for dict in jsonArray {
            guard let idString = dict["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let name = dict["name"] as? String,
                  let incomingModel = dict["incomingModel"] as? String,
                  let actualModel = dict["actualModel"] as? String,
                  let apiProviderString = dict["apiProvider"] as? String,
                  let apiProvider = APIProvider(rawValue: apiProviderString),
                  let baseURLString = dict["baseURL"] as? String,
                  let baseURL = URL(string: baseURLString) else {
                continue
            }

            let parameters: InjectedParameters
            if let paramsDict = dict["parameters"] as? [String: Any],
               let paramsData = try? JSONSerialization.data(withJSONObject: paramsDict),
               let decodedParams = try? JSONDecoder().decode(InjectedParameters.self, from: paramsData) {
                parameters = decodedParams
            } else {
                parameters = .empty
            }

            let isEnabled = dict["isEnabled"] as? Bool ?? true

            oldMappings.append(OldMapping(
                id: id,
                name: name,
                incomingModel: incomingModel,
                actualModel: actualModel,
                apiProvider: apiProvider,
                baseURL: baseURL,
                parameters: parameters,
                isEnabled: isEnabled
            ))
        }

        // Group by (apiProvider, baseURL)
        struct GroupKey: Hashable {
            let apiProvider: APIProvider
            let baseURL: URL
        }

        var groups: [GroupKey: [OldMapping]] = [:]
        // Preserve insertion order for stable naming
        var groupOrder: [GroupKey] = []

        for mapping in oldMappings {
            let key = GroupKey(apiProvider: mapping.apiProvider, baseURL: mapping.baseURL)
            if groups[key] == nil {
                groupOrder.append(key)
            }
            groups[key, default: []].append(mapping)
        }

        // Create ProviderConfig for each group and build new mappings
        var newProviders: [ProviderConfig] = []
        var newMappings: [ModelMapping] = []
        var providerCountByProvider: [APIProvider: Int] = [:]

        for key in groupOrder {
            guard let groupMappings = groups[key] else { continue }

            let count = providerCountByProvider[key.apiProvider, default: 0] + 1
            providerCountByProvider[key.apiProvider] = count

            let displayName = key.apiProvider.rawValue == "openai" ? "OpenAI" : "Anthropic"
            let providerName = count == 1 ? displayName : "\(displayName) \(count)"

            let provider = ProviderConfig(
                name: providerName,
                apiProvider: key.apiProvider,
                baseURL: key.baseURL
            )
            newProviders.append(provider)

            // Migrate API keys and create new mappings
            for oldMapping in groupMappings {
                let oldKey = oldMapping.id.uuidString
                let newKey = provider.id.uuidString
                if let apiKey = try? KeychainService.shared.retrieve(forKey: oldKey) {
                    try? KeychainService.shared.save(apiKey, forKey: newKey)
                }

                let newMapping = ModelMapping(
                    id: oldMapping.id,
                    name: oldMapping.name,
                    incomingModel: oldMapping.incomingModel,
                    actualModel: oldMapping.actualModel,
                    providerConfigId: provider.id,
                    parameters: oldMapping.parameters,
                    isEnabled: oldMapping.isEnabled
                )
                newMappings.append(newMapping)
            }
        }

        providers = newProviders
        mappings = newMappings
        saveProviders()
        save()

        defaults.set(true, forKey: migratedKey)
    }
}
