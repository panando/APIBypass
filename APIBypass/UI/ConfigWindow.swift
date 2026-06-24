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

    // Global toggle
    @AppStorage("preserveIncomingModel") private var preserveModelName: Bool = false
    @State private var showPreserveModelInfo = false

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
            Divider()
            preserveModelToggle
        }
        .alert(L10n.t("confirm_delete_provider"), isPresented: $showDeleteProviderConfirmation) {
            Button(L10n.t("cancel"), role: .cancel) {
                providerToDelete = nil
            }
            Button(L10n.t("delete"), role: .destructive) {
                if let provider = providerToDelete {
                    let relatedMappings = configManager.mappings.filter { $0.providerConfigId == provider.id }
                    Task {
                        for mapping in relatedMappings {
                            await configManager.delete(mapping.id)
                        }
                        await configManager.deleteProvider(provider.id)
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
                let count = configManager.mappings.filter { $0.providerConfigId == provider.id }.count
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
                // Chat Completions 提供商
                let openaiProviders = configManager.providers.filter { $0.apiProvider == .openai }
                if !openaiProviders.isEmpty {
                    Section(L10n.t("provider_group_chat_completions")) {
                        ForEach(openaiProviders) { provider in
                            providerRow(provider)
                        }
                        .onMove { source, destination in
                            Task {
                                await configManager.moveProvider(from: source, to: destination)
                            }
                        }
                    }
                }

                // Anthropic 提供商
                let anthropicProviders = configManager.providers.filter { $0.apiProvider == .anthropic }
                if !anthropicProviders.isEmpty {
                    Section(L10n.t("provider_group_anthropic")) {
                        ForEach(anthropicProviders) { provider in
                            providerRow(provider)
                        }
                        .onMove { source, destination in
                            Task {
                                await configManager.moveProvider(from: source, to: destination)
                            }
                        }
                    }
                }

                // Responses API 提供商
                let responsesProviders = configManager.providers.filter { $0.apiProvider == .responses }
                if !responsesProviders.isEmpty {
                    Section(L10n.t("provider_group_responses")) {
                        ForEach(responsesProviders) { provider in
                            providerRow(provider)
                        }
                        .onMove { source, destination in
                            Task {
                                await configManager.moveProvider(from: source, to: destination)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: ProviderConfig) -> some View {
        let isSelected = selectedProviderId == provider.id
        HStack(spacing: 10) {
            Image(systemName: iconForProvider(provider.apiProvider))
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

    private func iconForProvider(_ type: APIProvider) -> String {
        switch type {
        case .openai: return "building.2"
        case .anthropic: return "brain"
        case .responses: return "bolt"
        }
    }

    @ViewBuilder
    private var preserveModelToggle: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: $preserveModelName)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()

            Text(L10n.t("preserve_model_name"))
                .font(.system(size: 11))
                .lineLimit(1)

            Spacer()

            Button {
                showPreserveModelInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPreserveModelInfo) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("preserve_model_name"))
                        .font(.headline)
                    Text(L10n.t("preserve_model_name_desc"))
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.t("preserve_model_name_example"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(width: 280)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
           let provider = configManager.providers.first(where: { $0.id == pid }) {
            providerToDelete = provider
            showDeleteProviderConfirmation = true
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if let pid = selectedProviderId,
           configManager.providers.contains(where: { $0.id == pid }) {
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
                            if let provider = configManager.providers.first(where: { $0.id == mapping.providerConfigId }) {
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
        VStack(spacing: 20) {
            Spacer()

            // App Icon
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text(L10n.t("app_capabilities_title"))
                .font(.title2)
                .fontWeight(.medium)

            VStack(alignment: .leading, spacing: 10) {
                capabilityRow(
                    icon: "arrow.triangle.swap",
                    title: L10n.t("capability_model_mapping"),
                    description: L10n.t("capability_model_mapping_desc")
                )
                capabilityRow(
                    icon: "arrow.left.arrow.right",
                    title: L10n.t("capability_api_protocol"),
                    description: L10n.t("capability_api_protocol_desc")
                )
                capabilityRow(
                    icon: "brain.head.profile",
                    title: L10n.t("capability_thinking_protocol"),
                    description: L10n.t("capability_thinking_protocol_desc")
                )
                capabilityRow(
                    icon: "slider.horizontal.3",
                    title: L10n.t("capability_param_injection"),
                    description: L10n.t("capability_param_injection_desc")
                )
                capabilityRow(
                    icon: "terminal",
                    title: L10n.t("capability_claude_code"),
                    description: L10n.t("capability_claude_code_desc")
                )
                capabilityRow(
                    icon: "bolt",
                    title: L10n.t("capability_codex_adaptor"),
                    description: L10n.t("capability_codex_adaptor_desc")
                )
                capabilityRow(
                    icon: "lock.open",
                    title: L10n.t("capability_codex_unlock"),
                    description: L10n.t("capability_codex_unlock_desc")
                )
            }
            .padding(.horizontal, 48)

            Spacer()

            Button {
                showNewProviderSheet = true
            } label: {
                Label(L10n.t("create_provider"), systemImage: "plus.circle")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func capabilityRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copyProvider(_ provider: ProviderConfig) {
        let newProvider = ProviderConfig(
            name: provider.name + " 副本",
            apiProvider: provider.apiProvider,
            baseURL: provider.baseURL,
            environmentVariables: provider.environmentVariables,
            includeUsageInStreamRequests: provider.includeUsageInStreamRequests
        )

        let mappingsToCopy = configManager.mappings.filter { $0.providerConfigId == provider.id }
        Task {
            await configManager.addProvider(newProvider)

            if let apiKey = try? await keychain.retrieve(forKey: provider.id.uuidString) {
                try? await keychain.save(apiKey, forKey: newProvider.id.uuidString)
            }

            for mapping in mappingsToCopy {
                let newMapping = ModelMapping(
                    name: mapping.name,
                    incomingModel: mapping.incomingModel,
                    actualModel: mapping.actualModel,
                    providerConfigId: newProvider.id,
                    parameters: mapping.parameters,
                    isEnabled: mapping.isEnabled
                )
                await configManager.add(newMapping)
            }
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
