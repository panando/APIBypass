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

    private var hasChanges: Bool {
        name != originalName
            || apiProvider != originalApiProvider
            || baseURL != originalBaseURL
            || apiKey != originalApiKey
    }

    private var relatedMappings: [ModelMapping] {
        configManager.mappingsForProvider(providerId)
    }

    private var orphanMappings: [ModelMapping] {
        configManager.mappings.filter {
            configManager.findProvider(for: $0.providerConfigId) == nil
        }
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
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Model Mappings Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.t("related_mappings"))
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
                        VStack(spacing: 8) {
                            ForEach(relatedMappings) { mapping in
                                MappingCardView(
                                    configManager: configManager,
                                    keychain: keychain,
                                    mapping: mapping,
                                    onSave: {
                                        onSave?()
                                    },
                                    onDelete: {
                                        configManager.delete(mapping.id)
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

                // Orphan mappings
                if !orphanMappings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("未分类映射")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ForEach(orphanMappings) { mapping in
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text(mapping.name)
                                    .font(.body)
                                Text("\(mapping.incomingModel) -> \(mapping.actualModel)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                Spacer()
            }
            .padding()
        }
        .toolbar {
            Spacer()
            Button(action: {
                saveChanges()
            }) {
                Text(L10n.t("save"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hasChanges ? Color.accentColor : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(hasChanges ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .foregroundColor(hasChanges ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!hasChanges)
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
        .sheet(isPresented: $showNewMappingSheet) {
            NewMappingView(configManager: configManager, keychain: keychain)
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
            baseURL: URL(string: baseURL) ?? apiProvider.defaultBaseURL
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
