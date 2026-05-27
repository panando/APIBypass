import SwiftUI

struct ConfigWindow: View {
    @ObservedObject var configManager: ConfigManager
    @State private var selectedProviderId: UUID?
    @State private var showNewProviderSheet = false
    @State private var showDeleteProviderConfirmation = false
    @State private var providerToDelete: ProviderConfig?

    // Sidebar state
    @State private var sidebarVisible = true

    // Change tracking
    @State private var currentHasChanges = false
    @State private var pendingProviderId: UUID?
    @State private var showSwitchConfirmation = false
    @State private var forceResetTrigger = 0
    @State private var saveAndSwitchTrigger = 0

    @ObservedObject private var l10n = LocalizationManager.shared
    private let keychain = KeychainService.shared

    var body: some View {
        HStack(spacing: 0) {
            // Custom sidebar
            if sidebarVisible {
                sidebarContent
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
                Divider()
            }

            // Toggle button (always visible at left edge)
            Button {
                sidebarVisible.toggle()
            } label: {
                Image(systemName: sidebarVisible ? "sidebar.left" : "sidebar.right")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .help(sidebarVisible ? "隐藏边栏" : "显示边栏")

            // Detail area
            detailView
                .frame(minWidth: 400)
        }
        .navigationTitle("APIBypass")
        .sheet(isPresented: $showNewProviderSheet) {
            NewProviderView(configManager: configManager, keychain: keychain) { newProvider in
                selectedProviderId = newProvider.id
            }
        }
        .onAppear {
            let providerIds = configManager.providers.map { $0.id.uuidString }
            keychain.preloadKeys(for: providerIds)
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            providerList
            bottomToolbar
        }
        .alert(L10n.t("confirm_delete_provider"), isPresented: $showDeleteProviderConfirmation) {
            Button(L10n.t("cancel"), role: .cancel) {
                providerToDelete = nil
            }
            Button(L10n.t("delete"), role: .destructive) {
                if let provider = providerToDelete {
                    let relatedMappings = configManager.mappingsForProvider(provider.id)
                    for mapping in relatedMappings {
                        configManager.delete(mapping.id)
                    }
                    configManager.deleteProvider(provider.id)
                    try? keychain.delete(forKey: provider.id.uuidString)
                    if selectedProviderId == provider.id {
                        selectedProviderId = nil
                    }
                }
                providerToDelete = nil
            }
        } message: {
            if let provider = providerToDelete {
                let count = configManager.mappingsForProvider(provider.id).count
                if count > 0 {
                    Text("\(L10n.t("confirm_delete_provider_msg"))「\(provider.name)」\(L10n.t("confirm_delete_provider_hint_prefix"))\(count)\(L10n.t("confirm_delete_provider_hint_suffix"))")
                } else {
                    Text("\(L10n.t("confirm_delete_msg"))「\(provider.name)」\(L10n.t("confirm_delete_hint"))")
                }
            } else {
                Text(L10n.t("confirm_delete_generic"))
            }
        }
        .alert(L10n.t("unsaved_changes"), isPresented: $showSwitchConfirmation) {
            Button(L10n.t("cancel"), role: .cancel) {
                pendingProviderId = nil
            }
            Button(L10n.t("discard_changes"), role: .destructive) {
                if let pid = pendingProviderId {
                    currentHasChanges = false
                    selectedProviderId = pid
                    forceResetTrigger += 1
                }
                pendingProviderId = nil
            }
            Button(L10n.t("save_and_switch")) {
                if pendingProviderId != nil {
                    saveAndSwitchTrigger += 1
                }
                pendingProviderId = nil
            }
        } message: {
            Text(L10n.t("unsaved_changes_msg"))
        }
    }

    @ViewBuilder
    private var providerList: some View {
        List(selection: Binding<UUID?>(
            get: { selectedProviderId },
            set: { newId in
                if currentHasChanges && newId != selectedProviderId {
                    pendingProviderId = newId
                    showSwitchConfirmation = true
                } else {
                    selectedProviderId = newId
                }
            }
        )) {
            Section(L10n.t("providers")) {
                ForEach(configManager.providers) { provider in
                    providerRow(provider)
                }
                .onMove { source, destination in
                    configManager.moveProvider(from: source, to: destination)
                }
            }
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: ProviderConfig) -> some View {
        HStack {
            Image(systemName: provider.apiProvider == .openai ? "building.2" : "brain")
                .foregroundColor(.accentColor)
                .frame(width: 16)
            VStack(alignment: .leading) {
                Text(provider.name)
                    .font(.headline)
                Text(provider.baseURL.host ?? provider.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .tag(provider.id)
        .contextMenu {
            Button {
                copyProvider(provider)
            } label: {
                Label(L10n.t("copy_provider"), systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                providerToDelete = provider
                showDeleteProviderConfirmation = true
            } label: {
                Label(L10n.t("delete_provider"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            Button {
                showNewProviderSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("添加")
                }
            }

            Spacer()

            Button {
                deleteSelected()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "minus")
                    Text("删除")
                }
            }
            .disabled(selectedProviderId == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func deleteSelected() {
        if let pid = selectedProviderId,
           let provider = configManager.findProvider(for: pid) {
            providerToDelete = provider
            showDeleteProviderConfirmation = true
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let pid = selectedProviderId,
           configManager.findProvider(for: pid) != nil {
            HStack(spacing: 0) {
                ProviderDetailView(
                    configManager: configManager,
                    providerId: pid,
                    keychain: keychain,
                    onHasChangesChange: { hasChanges in
                        currentHasChanges = hasChanges
                    },
                    onSave: {
                        currentHasChanges = false
                    },
                    forceResetTrigger: forceResetTrigger,
                    saveTrigger: saveAndSwitchTrigger
                )
                .id(pid)

                Divider()

                mappingListPanel
            }
        } else {
            emptyStateView
        }
    }

    @ViewBuilder
    private var mappingListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("model_mappings"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            if configManager.mappings.isEmpty {
                Text("暂无映射")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(configManager.mappings) { mapping in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Circle()
                                    .fill(mapping.isEnabled ? Color.green : Color.gray)
                                    .frame(width: 6, height: 6)
                                Text(mapping.name)
                                    .font(.body)
                                    .lineLimit(1)
                            }
                            Text("\(mapping.incomingModel) → \(mapping.actualModel)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            if let provider = configManager.findProvider(for: mapping.providerConfigId) {
                                Text(provider.name)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 220)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(L10n.t("select_or_create"))
                .font(.title2)
                .foregroundColor(.secondary)
            Text(L10n.t("select_or_create_hint"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showNewProviderSheet = true
            } label: {
                Label(L10n.t("create_provider"), systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func copyProvider(_ provider: ProviderConfig) {
        let newProvider = ProviderConfig(
            name: provider.name + " 副本",
            apiProvider: provider.apiProvider,
            baseURL: provider.baseURL
        )

        configManager.addProvider(newProvider)

        if let apiKey = try? keychain.retrieve(forKey: provider.id.uuidString) {
            try? keychain.save(apiKey, forKey: newProvider.id.uuidString)
        }

        let mappingsToCopy = configManager.mappingsForProvider(provider.id)
        for mapping in mappingsToCopy {
            let newMapping = ModelMapping(
                name: mapping.name,
                incomingModel: mapping.incomingModel,
                actualModel: mapping.actualModel,
                providerConfigId: newProvider.id,
                parameters: mapping.parameters,
                isEnabled: mapping.isEnabled
            )
            configManager.add(newMapping)
        }

        selectedProviderId = newProvider.id
    }
}
