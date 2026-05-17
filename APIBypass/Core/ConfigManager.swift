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
        if let json = String(data: data, encoding: .utf8) {
            print("[Config] 保存 \(mappings.count) 条映射: \(json)")
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ModelMapping].self, from: data) else {
            mappings = []
            print("[Config] 未找到已保存配置, 初始化为空")
            return
        }
        mappings = decoded
        print("[Config] 加载 \(mappings.count) 条映射")
        for m in mappings {
            print("[Config]   - id=\(m.id) name=\(m.name) incoming=\(m.incomingModel) actual=\(m.actualModel) thinking=\(String(describing: m.parameters.thinking))")
        }
    }
}
