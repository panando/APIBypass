import SwiftUI

struct ProviderDetailView: View {
    @ObservedObject var configManager: ConfigManager
    let providerId: UUID
    let keychain: KeychainService

    var onHasChangesChange: ((Bool) -> Void)?
    var onSave: (() -> Void)?
    var forceResetTrigger: Int = 0
    var saveTrigger: Int = 0

    @ObservedObject private var l10n = LocalizationManager.shared

    @State private var name: String = ""
    @State private var apiProvider: APIProvider = .openai
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var showSaveConfirmation = false

    @State private var originalName: String = ""
    @State private var originalApiProvider: APIProvider = .openai
    @State private var originalBaseURL: String = ""
    @State private var originalApiKey: String = ""
    @State private var lastResetTrigger = 0
    @State private var lastSaveTrigger = 0

    // Mapping creation sheet
    @State private var showNewMappingSheet = false

    // Track expanded mapping and unsaved changes
    @State private var expandedMappingId: UUID?
    @State private var mappingWithChanges: UUID?
    @State private var showMappingSwitchAlert = false
    @State private var pendingMappingId: UUID?

    private var hasChanges: Bool {
        name != originalName
            || apiProvider != originalApiProvider
            || baseURL != originalBaseURL
            || apiKey != originalApiKey
    }

    private var relatedMappings: [ModelMapping] {
        configManager.mappingsForProvider(providerId)
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
                                Text("OpenAI").tag(APIProvider.openai)
                                Text("Anthropic").tag(APIProvider.anthropic)
                            }
                            .pickerStyle(.menu)
                            .onChange(of: apiProvider) { _, newValue in
                                if baseURL.isEmpty || baseURL == APIProvider.openai.defaultBaseURL.absoluteString || baseURL == APIProvider.anthropic.defaultBaseURL.absoluteString {
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
                                        configManager.delete(mapping.id)
                                    },
                                    onHasChangesChange: { hasChanges in
                                        if hasChanges {
                                            mappingWithChanges = mapping.id
                                        } else if mappingWithChanges == mapping.id {
                                            mappingWithChanges = nil
                                        }
                                    }
                                )
                            }
                            .onMove { source, destination in
                                configManager.moveMapping(providerId: providerId, from: source, to: destination)
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
                    expandedMappingId = id
                }
                mappingWithChanges = nil
                pendingMappingId = nil
            }
            Button(L10n.t("save_and_switch")) {
                pendingMappingId = nil
            }
        } message: {
            Text(L10n.t("unsaved_changes_msg"))
        }
        .sheet(isPresented: $showNewMappingSheet) {
            NewMappingView(configManager: configManager, keychain: keychain, defaultProviderId: providerId)
        }
    }

    private func loadProviderData() {
        guard let provider = configManager.findProvider(for: providerId) else { return }
        name = provider.name
        apiProvider = provider.apiProvider
        baseURL = provider.baseURL.absoluteString

        if let key = try? keychain.retrieve(forKey: providerId.uuidString) {
            apiKey = key
        }

        loadOriginalData()
    }

    private func loadOriginalData() {
        originalName = name
        originalApiProvider = apiProvider
        originalBaseURL = baseURL
        originalApiKey = apiKey
        onHasChangesChange?(false)
    }

    private func saveChanges() {
        guard let provider = configManager.findProvider(for: providerId) else { return }

        let updatedProvider = ProviderConfig(
            id: provider.id,
            name: name,
            apiProvider: apiProvider,
            baseURL: URL(string: baseURL) ?? apiProvider.defaultBaseURL,
            environmentVariables: provider.environmentVariables
        )

        configManager.updateProvider(updatedProvider)

        if !apiKey.isEmpty {
            try? keychain.save(apiKey, forKey: providerId.uuidString)
        }

        onSave?()
        showSaveConfirmation = true
    }

    func discardChanges() {
        loadProviderData()
    }
}
