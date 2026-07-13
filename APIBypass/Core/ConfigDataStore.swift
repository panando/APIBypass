import Foundation

/// Thread-safe actor for managing configuration data
actor ConfigDataStore {
    static let shared = ConfigDataStore()

    private(set) var mappings: [ModelMapping] = []
    private(set) var providers: [ProviderConfig] = []

    private let defaultsKey = "com.apibypass.mappings"
    private let providersDefaultsKey = "com.apibypass.providers"
    private let migratedKey = "com.apibypass.migratedToProviders"
    private let defaults = UserDefaults.standard
    private var isInitialized = false

    private init() {
        // Synchronous initialization - load data directly from UserDefaults
        // UserDefaults is thread-safe for reads
    }

    /// Ensure data is loaded (call this before any data access)
    private func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = true

        // Load synchronously within actor
        loadProvidersSync()
        loadSync()
        migrateIfNeededSync()
        cleanupOrphanMappingsSync()
        migrateProviderEnvironmentVariablesSync()
    }

    // MARK: - Read Operations

    func getMappings() -> [ModelMapping] {
        ensureInitialized()
        return mappings
    }

    func getProviders() -> [ProviderConfig] {
        ensureInitialized()
        return providers
    }

    func findMapping(for model: String) -> ModelMapping? {
        ensureInitialized()
        return mappings.first { $0.matches(model: model) }
    }

    func getFirstEnabledMapping() -> ModelMapping? {
        ensureInitialized()
        return mappings.first { $0.isEnabled }
    }

    func findProvider(for id: UUID) -> ProviderConfig? {
        ensureInitialized()
        return providers.first { $0.id == id }
    }

    func mappingsForProvider(_ providerId: UUID) -> [ModelMapping] {
        ensureInitialized()
        return mappings.filter { $0.providerConfigId == providerId }
    }

    func isProviderValid(for mapping: ModelMapping) -> Bool {
        ensureInitialized()
        return providers.contains { $0.id == mapping.providerConfigId }
    }

    // MARK: - Mapping CRUD

    func add(_ mapping: ModelMapping) {
        ensureInitialized()
        mappings.append(mapping)
        saveSync()
    }

    func update(_ mapping: ModelMapping) {
        ensureInitialized()
        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = mapping
            saveSync()
        }
    }

    func deleteMapping(_ id: UUID) {
        ensureInitialized()
        mappings.removeAll { $0.id == id }
        saveSync()
    }

    // MARK: - Provider CRUD

    func addProvider(_ provider: ProviderConfig) {
        ensureInitialized()
        providers.append(provider)
        saveProvidersSync()
    }

    func updateProvider(_ provider: ProviderConfig) {
        ensureInitialized()
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
            saveProvidersSync()
        }
    }

    func deleteProvider(_ id: UUID) {
        ensureInitialized()
        providers.removeAll { $0.id == id }
        saveProvidersSync()
    }

    // MARK: - Reordering

    func moveProvider(_ apiProvider: APIProvider, from source: IndexSet, to destination: Int) {
        ensureInitialized()
        // 该 apiProvider 在全局数组中占用的槽位（升序）。组内排列不改变这些槽位，
        // 只是把组内元素在这些固定槽位间重排，因此非组元素原位不动。
        let slots = providers.indices.filter { providers[$0].apiProvider == apiProvider }
        guard !slots.isEmpty else { return }

        // `.onMove` 给的 source/destination 是相对该组过滤后子集的局部偏移，
        // 与 Array.move 的 after-removal 帧语义天然对齐。
        var group = providers.filter { $0.apiProvider == apiProvider }
        group.move(fromOffsets: source, toOffset: destination)

        // 回填到原槽位
        for (i, slot) in slots.enumerated() where i < group.count {
            providers[slot] = group[i]
        }
        saveProvidersSync()
    }

    func moveMapping(providerId: UUID, from source: IndexSet, to destination: Int) {
        ensureInitialized()
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
        saveSync()
    }

    // MARK: - Persistence (Sync versions for actor)

    private func saveSync() {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func loadSync() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ModelMapping].self, from: data) else {
            mappings = []
            return
        }
        mappings = decoded
    }

    private func saveProvidersSync() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        defaults.set(data, forKey: providersDefaultsKey)
    }

    private func loadProvidersSync() {
        guard let data = defaults.data(forKey: providersDefaultsKey),
              let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: data) else {
            providers = []
            return
        }
        providers = decoded
    }

    // MARK: - Cleanup & Migration (Sync versions)

    private func cleanupOrphanMappingsSync() {
        let validIds = Set(providers.map { $0.id })
        let orphans = mappings.filter { !validIds.contains($0.providerConfigId) }
        if !orphans.isEmpty {
            mappings.removeAll { !validIds.contains($0.providerConfigId) }
            saveSync()
            print("[Cleanup] Removed \(orphans.count) orphan mapping(s) with invalid provider")
        }
    }

    private func migrateProviderEnvironmentVariablesSync() {
        var needsSave = false

        for index in providers.indices {
            if providers[index].environmentVariables.isEmpty {
                providers[index].environmentVariables = ProviderConfig.defaultEnvironmentVariables()
                needsSave = true
            }
        }

        if needsSave {
            saveProvidersSync()
            print("[Migration] Added default environment variables to \(providers.count) provider(s)")
        }
    }

    private func migrateIfNeededSync() {
        guard !defaults.bool(forKey: migratedKey) else { return }

        guard let data = defaults.data(forKey: defaultsKey) else {
            defaults.set(true, forKey: migratedKey)
            return
        }

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            defaults.set(true, forKey: migratedKey)
            return
        }

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

        struct GroupKey: Hashable {
            let apiProvider: APIProvider
            let baseURL: URL
        }

        var groups: [GroupKey: [OldMapping]] = [:]
        var groupOrder: [GroupKey] = []

        for mapping in oldMappings {
            let key = GroupKey(apiProvider: mapping.apiProvider, baseURL: mapping.baseURL)
            if groups[key] == nil {
                groupOrder.append(key)
            }
            groups[key, default: []].append(mapping)
        }

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

            for oldMapping in groupMappings {
                let oldKey = oldMapping.id.uuidString
                let newKey = provider.id.uuidString
                // Migrate API keys asynchronously
                Task {
                    if let apiKey = try? await KeychainService.shared.retrieve(forKey: oldKey) {
                        try? await KeychainService.shared.save(apiKey, forKey: newKey)
                    }
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
        saveProvidersSync()
        saveSync()

        defaults.set(true, forKey: migratedKey)
    }
}
