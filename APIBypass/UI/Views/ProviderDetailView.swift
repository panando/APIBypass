import SwiftUI

struct ProviderDetailView: View {
    @ObservedObject var configManager: ConfigManager
    let providerId: UUID
    let keychain: KeychainService

    var onHasChangesChange: ((Bool) -> Void)?
    var onSave: (() -> Void)?
    var forceResetTrigger: Int = 0
    var saveTrigger: Int = 0

    private let l10n = LocalizationManager.shared

    @State private var name: String = ""
    @State private var apiProvider: APIProvider = .openai
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var includeUsageInStreamRequests = true
    @State private var showStreamUsageInfo = false
    @State private var showSaveConfirmation = false

    @State private var originalName: String = ""
    @State private var originalApiProvider: APIProvider = .openai
    @State private var originalBaseURL: String = ""
    @State private var originalApiKey: String = ""
    @State private var originalIncludeUsageInStreamRequests = true
    @State private var lastResetTrigger = 0
    @State private var lastSaveTrigger = 0

    // Mapping creation sheet
    @State private var showNewMappingSheet = false

    // Track expanded mapping and unsaved changes
    @State private var expandedMappingId: UUID?
    @State private var mappingWithChanges: UUID?
    @State private var showMappingSwitchAlert = false
    @State private var pendingMappingId: UUID?
    @State private var mappingSaveTrigger = 0
    @State private var draggingMappingId: UUID?

    private var hasChanges: Bool {
        name != originalName
            || apiProvider != originalApiProvider
            || baseURL != originalBaseURL
            || apiKey != originalApiKey
            || includeUsageInStreamRequests != originalIncludeUsageInStreamRequests
    }

    private var relatedMappings: [ModelMapping] {
        configManager.mappings.filter { $0.providerConfigId == providerId }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Provider Info Section
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("provider_info"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        HStack {
                            Text(L10n.t("provider_name"))
                                .frame(width: 100, alignment: .trailing)
                            TextField(L10n.t("provider_name_placeholder"), text: $name)
                        }
                        HStack {
                            Text(L10n.t("api_provider"))
                                .frame(width: 100, alignment: .trailing)
                            Picker("", selection: $apiProvider) {
                                Text(L10n.t("provider_type_openai")).tag(APIProvider.openai)
                                Text(L10n.t("provider_type_anthropic")).tag(APIProvider.anthropic)
                                Text(L10n.t("provider_type_responses")).tag(APIProvider.responses)
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offset(x: -8)
                            .onChange(of: apiProvider) { _, newValue in
                                if baseURL.isEmpty || baseURL == APIProvider.openai.defaultBaseURL.absoluteString || baseURL == APIProvider.anthropic.defaultBaseURL.absoluteString || baseURL == APIProvider.responses.defaultBaseURL.absoluteString {
                                    baseURL = newValue.defaultBaseURL.absoluteString
                                }
                            }
                        }
                        HStack {
                            Text(L10n.t("base_url"))
                                .frame(width: 100, alignment: .trailing)
                            TextField(L10n.t("base_url_placeholder"), text: $baseURL)
                        }
                        HStack {
                            Text(L10n.t("api_key"))
                                .frame(width: 100, alignment: .trailing)
                            SecureField(L10n.t("api_key_placeholder"), text: $apiKey)
                        }
                        if apiProvider == .openai {
                            HStack(spacing: 6) {
                                Toggle("", isOn: $includeUsageInStreamRequests)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .labelsHidden()
                                Text(L10n.t("stream_usage_toggle"))
                                    .lineLimit(1)
                                Button {
                                    showStreamUsageInfo.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showStreamUsageInfo) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(L10n.t("stream_usage_toggle"))
                                            .font(.headline)
                                        Text(L10n.t("stream_usage_desc"))
                                            .font(.body)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(12)
                                    .frame(width: 320)
                                }
                                Spacer()
                            }
                            .padding(.leading, 100)
                            .padding(.top, 4)
                        }
                    }

                    // Responses API warning banner
                    if apiProvider == .responses {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text(L10n.t("provider_responses_note_title"))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            Text(L10n.t("provider_responses_note_desc"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                        .padding(.top, 8)
                    }

                    // Save button inside provider card
                    if hasChanges {
                        HStack {
                            Spacer()
                            Button(action: {
                                saveChanges()
                            }) {
                                Text(L10n.t("save"))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.accentColor)
                                    )
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.defaultAction)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Model Mappings Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(L10n.t("model_mappings"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            showNewMappingSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text(L10n.t("add_mapping"))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if relatedMappings.isEmpty {
                        Text(L10n.t("select_or_create_hint"))
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(relatedMappings) { mapping in
                                MappingCardView(
                                    configManager: configManager,
                                    keychain: keychain,
                                    mapping: mapping,
                                    isExpanded: Binding(
                                        get: { expandedMappingId == mapping.id },
                                        set: { newValue in
                                            if newValue {
                                                if let currentId = expandedMappingId,
                                                   currentId != mapping.id,
                                                   mappingWithChanges != nil {
                                                    pendingMappingId = mapping.id
                                                    showMappingSwitchAlert = true
                                                } else {
                                                    expandedMappingId = mapping.id
                                                }
                                            } else {
                                                if mappingWithChanges != mapping.id {
                                                    expandedMappingId = nil
                                                }
                                            }
                                        }
                                    ),
                                    onSave: {
                                        expandedMappingId = nil
                                        mappingWithChanges = nil
                                        onSave?()
                                    },
                                    onDelete: {
                                        if expandedMappingId == mapping.id {
                                            expandedMappingId = nil
                                            mappingWithChanges = nil
                                        }
                                        Task {
                                            await configManager.delete(mapping.id)
                                        }
                                    },
                                    onHasChangesChange: { hasChanges in
                                        if hasChanges {
                                            mappingWithChanges = mapping.id
                                        } else if mappingWithChanges == mapping.id {
                                            mappingWithChanges = nil
                                        }
                                    },
                                    externalSaveTrigger: mappingSaveTrigger
                                )
                                .opacity(draggingMappingId == mapping.id ? 0.6 : 1)
                                .onDrag {
                                    draggingMappingId = mapping.id
                                    return NSItemProvider(object: mapping.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: MappingDropDelegate(
                                    targetMapping: mapping,
                                    relatedMappings: relatedMappings,
                                    draggingMappingId: $draggingMappingId,
                                    move: { source, destination in
                                        Task {
                                            await configManager.moveMapping(providerId: providerId, from: source, to: destination)
                                        }
                                    }
                                ))
                            }
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Spacer()
            }
            .padding()
        }
        .onAppear {
            loadProviderData()
        }
        .onChange(of: hasChanges) { _, newValue in
            onHasChangesChange?(newValue)
        }
        .onChange(of: forceResetTrigger) { _, newValue in
            if newValue != lastResetTrigger {
                lastResetTrigger = newValue
                loadProviderData()
            }
        }
        .onChange(of: saveTrigger) { _, newValue in
            if newValue != lastSaveTrigger && hasChanges {
                lastSaveTrigger = newValue
                saveChanges()
            }
        }
        .alert(L10n.t("saved"), isPresented: $showSaveConfirmation) {
            Button(L10n.t("ok"), role: .cancel) {
                loadOriginalData()
            }
        }
        .alert(L10n.t("unsaved_changes"), isPresented: $showMappingSwitchAlert) {
            Button(L10n.t("cancel"), role: .cancel) {
                pendingMappingId = nil
            }
            Button(L10n.t("discard_changes"), role: .destructive) {
                if let id = pendingMappingId {
                    mappingWithChanges = nil
                    expandedMappingId = id
                }
                pendingMappingId = nil
            }
            Button(L10n.t("save_and_switch")) {
                mappingSaveTrigger += 1
                if let id = pendingMappingId {
                    mappingWithChanges = nil
                    expandedMappingId = id
                }
                pendingMappingId = nil
            }
        } message: {
            Text(L10n.t("unsaved_changes_msg"))
        }
        .sheet(isPresented: $showNewMappingSheet) {
            NewMappingView(configManager: configManager, keychain: keychain, defaultProviderId: providerId)
        }
        .onChange(of: relatedMappings.count) { _, _ in
            // 当映射数量变化时（新建或删除），清除未保存状态
            mappingWithChanges = nil
        }
    }

    private func loadProviderData() {
        guard let provider = configManager.providers.first(where: { $0.id == providerId }) else { return }
        name = provider.name
        apiProvider = provider.apiProvider
        baseURL = provider.baseURL.absoluteString
        includeUsageInStreamRequests = provider.includeUsageInStreamRequests

        Task {
            if let key = try? await keychain.retrieve(forKey: providerId.uuidString) {
                apiKey = key
            }
            loadOriginalData()
        }
    }

    private func loadOriginalData() {
        originalName = name
        originalApiProvider = apiProvider
        originalBaseURL = baseURL
        originalApiKey = apiKey
        originalIncludeUsageInStreamRequests = includeUsageInStreamRequests
        onHasChangesChange?(false)
    }

    private func saveChanges() {
        guard let provider = configManager.providers.first(where: { $0.id == providerId }) else { return }

        let updatedProvider = ProviderConfig(
            id: provider.id,
            name: name,
            apiProvider: apiProvider,
            baseURL: URL(string: baseURL) ?? apiProvider.defaultBaseURL,
            environmentVariables: provider.environmentVariables,
            includeUsageInStreamRequests: includeUsageInStreamRequests
        )

        Task {
            await configManager.updateProvider(updatedProvider)

            if !apiKey.isEmpty {
                try? await keychain.save(apiKey, forKey: providerId.uuidString)
            }
        }

        onSave?()
        showSaveConfirmation = true
    }

    func discardChanges() {
        loadProviderData()
    }
}

private struct MappingDropDelegate: DropDelegate {
    let targetMapping: ModelMapping
    let relatedMappings: [ModelMapping]
    @Binding var draggingMappingId: UUID?
    let move: (IndexSet, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingMappingId,
              draggingMappingId != targetMapping.id,
              let sourceIndex = relatedMappings.firstIndex(where: { $0.id == draggingMappingId }),
              let targetIndex = relatedMappings.firstIndex(where: { $0.id == targetMapping.id }) else { return }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        move(IndexSet(integer: sourceIndex), destination)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingMappingId = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
