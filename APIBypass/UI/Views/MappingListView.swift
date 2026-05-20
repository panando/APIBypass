import SwiftUI

struct MappingListView: View {
    @ObservedObject var configManager: ConfigManager
    @Binding var selectedMappingId: UUID?

    var onCopy: ((ModelMapping) -> Void)?
    var onDelete: ((ModelMapping) -> Void)?

    var body: some View {
        List(selection: $selectedMappingId) {
            ForEach(configManager.mappings) { mapping in
                HStack {
                    Circle()
                        .fill(mapping.isEnabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading) {
                        Text(mapping.name)
                            .font(.headline)
                        Text("\(mapping.incomingModel) → \(mapping.actualModel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .tag(mapping.id)
                .contextMenu {
                    Button {
                        onCopy?(mapping)
                    } label: {
                        Label("复制配置", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive) {
                        onDelete?(mapping)
                    } label: {
                        Label("删除配置", systemImage: "trash")
                    }
                }
            }
        }
        .frame(minWidth: 200)
    }
}
