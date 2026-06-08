import SwiftUI

struct MappingListView: View {
    @ObservedObject var configManager: ConfigManager
    @Binding var selectedMappingId: UUID?
    private let l10n = LocalizationManager.shared

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
                        let providerName = configManager.providers.first { $0.id == mapping.providerConfigId }?.name ?? L10n.t("provider_missing")
                        Text("\(mapping.incomingModel) → \(mapping.actualModel) · \(providerName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .tag(mapping.id)
                .contextMenu {
                    Button {
                        onCopy?(mapping)
                    } label: {
                        Label(L10n.t("copy_config"), systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive) {
                        onDelete?(mapping)
                    } label: {
                        Label(L10n.t("delete_config"), systemImage: "trash")
                    }
                }
            }
        }
        .frame(minWidth: 200)
    }
}
