import SwiftUI

struct MappingListView: View {
    @ObservedObject var configManager: ConfigManager
    @Binding var selectedMappingId: UUID?

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
            }
        }
        .frame(minWidth: 200)
    }
}
