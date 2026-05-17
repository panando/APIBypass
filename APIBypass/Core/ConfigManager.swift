import Foundation
import Combine

final class ConfigManager: ObservableObject {
    @Published var mappings: [ModelMapping] = []

    private let defaultsKey: String
    private let defaults = UserDefaults.standard

    init(defaultsKey: String = "com.apibypass.mappings") {
        self.defaultsKey = defaultsKey
        load()
    }

    func add(_ mapping: ModelMapping) {
        mappings.append(mapping)
        save()
    }

    func update(_ mapping: ModelMapping) {
        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = mapping
            save()
            print("[ConfigManager] 已更新映射 '\(mapping.name)': incoming=\(mapping.incomingModel), actual=\(mapping.actualModel), thinking=\(String(describing: mapping.parameters.thinking)), customFields=\(mapping.parameters.customFields?.count ?? 0)个")
        }
    }

    func delete(_ id: UUID) {
        mappings.removeAll { $0.id == id }
        save()
    }

    func findMapping(for model: String) -> ModelMapping? {
        mappings.first { $0.matches(model: model) }
    }

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
}
