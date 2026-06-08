import SwiftUI

struct ConfigWindow: View {
    @ObservedObject var configManager: ConfigManager
    @State private var selectedProviderId: UUID?
    @State private var showNewProviderSheet = false
    @State private var showDeleteProviderConfirmation = false
    @State private var providerToDelete: ProviderConfig?

    // Sidebar state
    @State private var sidebarVisible = true
    @State private var mappingPanelVisible = false  // Default hidden
    @State private var sidebarWidth: CGFloat = 200
    @State private var mappingPanelWidth: CGFloat = 180

    // Change tracking
    @State private var currentHasChanges = false
    @State private var pendingProviderId: UUID?
    @State private var showSwitchConfirmation = false
    @State private var forceResetTrigger = 0
    @State private var saveAndSwitchTrigger = 0

    private let l10n = LocalizationManager.shared
    private let keychain = KeychainService.shared

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebarContent
                    .frame(width: sidebarWidth)
                draggableDivider(width: $sidebarWidth, range: 180...400, visible: sidebarVisible)
            }

            detailView
                .frame(minWidth: 400)

            if mappingPanelVisible {
                draggableDivider(width: $mappingPanelWidth, range: 160...400, visible: mappingPanelVisible, reverse: true)
                mappingListPanel
                    .frame(width: mappingPanelWidth)
            }
        }
        .frame(minWidth: 900, minHeight: 500)
        .navigationTitle("APIBypass")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    sidebarVisible.toggle()
                } label: {
                    Image(systemName: sidebarVisible ? "sidebar.left" : "sidebar.right")
                }
                .help(sidebarVisible ? L10n.t("hide_provider_sidebar") : L10n.t("show_provider_sidebar"))
            }
            if !configManager.mappings.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        mappingPanelVisible.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mappingPanelVisible ? "sidebar.right" : "sidebar.right")
                            Text(L10n.t("mapping_status"))
                        }
                    }
                    .help(L10n.t("toggle_mapping_panel"))
                }
            }
        }
        .sheet(isPresented: $showNewProviderSheet) {
            NewProviderView(configManager: configManager, keychain: keychain) { newProvider in
                selectedProviderId = newProvider.id
            }
        }
        .onAppear {
            let providerIds = configManager.providers.map { $0.id.uuidString }
            Task {
                await keychain.preloadKeys(for: providerIds)
            }
        }
    }

    // MARK: - Draggable Divider

    @ViewBuilder
    private func draggableDivider(width: Binding<CGFloat>, range: ClosedRange<CGFloat>, visible: Bool, reverse: Bool = false) -> some View {
        if visible {
            DraggableDivider(width: width, range: range, reverse: reverse)
        }
    }

    // MARK: - Sidebar Content

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
                    Task {
                        try? await keychain.delete(forKey: provider.id.uuidString)
                    }
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
        VStack(spacing: 0) {
            // Custom section header
            Text(L10n.t("providers"))
                .font(.headline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.6))

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
                Section {
                    ForEach(configManager.providers) { provider in
                        providerRow(provider)
                    }
                    .onMove { source, destination in
                        configManager.moveProvider(from: source, to: destination)
                    }
                } header: {
                    EmptyView()
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: ProviderConfig) -> some View {
        let isSelected = selectedProviderId == provider.id
        HStack(spacing: 10) {
            Image(systemName: provider.apiProvider == .openai ? "building.2" : "brain")
                .foregroundColor(isSelected ? .white : .accentColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.system(size: 13, weight: .medium))
                Text(provider.baseURL.host ?? provider.baseURL.absoluteString)
                    .font(.system(size: 11))
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
                    Text(L10n.t("add_short"))
                }
            }

            Spacer()

            Button {
                deleteSelected()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "minus")
                    Text(L10n.t("delete_short"))
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

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if let pid = selectedProviderId,
           configManager.findProvider(for: pid) != nil {
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
        } else {
            emptyStateView
        }
    }

    @ViewBuilder
    private var mappingListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("mapping_status"))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.6))

            Divider()

            if configManager.mappings.isEmpty {
                Text(L10n.t("no_mappings"))
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
            baseURL: provider.baseURL,
            environmentVariables: provider.environmentVariables
        )

        configManager.addProvider(newProvider)

        Task {
            if let apiKey = try? await keychain.retrieve(forKey: provider.id.uuidString) {
                try? await keychain.save(apiKey, forKey: newProvider.id.uuidString)
            }
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

// MARK: - Draggable Divider View

struct DraggableDivider: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    var reverse: Bool = false

    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { value in
                        let delta = reverse ? -value.translation.width : value.translation.width
                        let newWidth = width + delta
                        width = min(max(newWidth, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.resizeLeftRight.pop()
                }
            }
    }
}
