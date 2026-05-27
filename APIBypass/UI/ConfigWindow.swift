import SwiftUI

struct ConfigWindow: View {
    @ObservedObject var configManager: ConfigManager
    @State private var selectedMappingId: UUID?
    @State private var selectedProviderId: UUID?
    @State private var showNewMappingSheet = false
    @State private var showNewProviderSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showDeleteProviderConfirmation = false
    @State private var mappingToDelete: ModelMapping?
    @State private var providerToDelete: ProviderConfig?

    // 变更追踪
    @State private var currentHasChanges = false
    @State private var pendingSelection: SelectionTarget?
    @State private var targetSelection: SelectionTarget?
    @State private var showSwitchConfirmation = false
    @State private var forceResetTrigger = 0
    @State private var saveAndSwitchTrigger = 0

    @ObservedObject private var l10n = LocalizationManager.shared
    private let keychain = KeychainService.shared

    enum SelectionTarget: Equatable, Hashable {
        case provider(UUID)
        case mapping(UUID)
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailView
        }
        .sheet(isPresented: $showNewProviderSheet) {
            NewProviderView(configManager: configManager, keychain: keychain) { newProvider in
                selectedProviderId = newProvider.id
                selectedMappingId = nil
            }
        }
        .sheet(isPresented: $showNewMappingSheet) {
            NewMappingView(configManager: configManager, keychain: keychain)
        }
        .onAppear {
            let providerIds = configManager.providers.map { $0.id.uuidString }
            keychain.preloadKeys(for: providerIds)
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        VStack {
            mainList
            bottomToolbar
        }
        .navigationTitle("APIBypass")
        .alert(L10n.t("confirm_delete_mapping"), isPresented: $showDeleteConfirmation) {
            deleteMappingAlertButtons
        } message: {
            deleteMappingAlertMessage
        }
        .alert(L10n.t("confirm_delete_provider"), isPresented: $showDeleteProviderConfirmation) {
            deleteProviderAlertButtons
        } message: {
            deleteProviderAlertMessage
        }
        .alert(L10n.t("unsaved_changes"), isPresented: $showSwitchConfirmation) {
            unsavedChangesAlertButtons
        } message: {
            Text(L10n.t("unsaved_changes_msg"))
        }
    }

    @ViewBuilder
    private var mainList: some View {
        List {
            providerSection
            mappingSection
        }
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private var providerSection: some View {
        Section(L10n.t("providers")) {
            ForEach(configManager.providers) { provider in
                providerRow(provider)
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
        .tag(SelectionTarget.provider(provider.id))
        .contextMenu {
            Button(role: .destructive) {
                providerToDelete = provider
                showDeleteProviderConfirmation = true
            } label: {
                Label(L10n.t("delete_provider"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var mappingSection: some View {
        Section(L10n.t("model_mappings")) {
            ForEach(configManager.mappings) { mapping in
                mappingRow(mapping)
            }
        }
    }

    @ViewBuilder
    private func mappingRow(_ mapping: ModelMapping) -> some View {
        HStack {
            Circle()
                .fill(mapping.isEnabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading) {
                Text(mapping.name)
                    .font(.headline)
                let providerName = configManager.findProvider(for: mapping.providerConfigId)?.name ?? L10n.t("provider_missing")
                Text("\(mapping.incomingModel) → \(mapping.actualModel) · \(providerName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .tag(SelectionTarget.mapping(mapping.id))
        .contextMenu {
            Button {
                copyMapping(mapping)
            } label: {
                Label(L10n.t("copy_config"), systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                mappingToDelete = mapping
                showDeleteConfirmation = true
            } label: {
                Label(L10n.t("delete_config"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var bottomToolbar: some View {
        HStack {
            Button {
                showNewProviderSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .help(L10n.t("add_provider"))

            Button {
                showNewMappingSheet = true
            } label: {
                Image(systemName: "plus.square")
            }
            .help(L10n.t("add_mapping"))

            Spacer()

            Button {
                deleteSelected()
            } label: {
                Image(systemName: "minus")
            }
            .help(L10n.t("delete_selected"))
            .disabled(currentSelection == nil)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Alert Components

    @ViewBuilder
    private var deleteMappingAlertButtons: some View {
        Button(L10n.t("cancel"), role: .cancel) {
            mappingToDelete = nil
        }
        Button(L10n.t("delete"), role: .destructive) {
            if let mapping = mappingToDelete {
                configManager.delete(mapping.id)
                if selectedMappingId == mapping.id {
                    selectedMappingId = nil
                }
            }
            mappingToDelete = nil
        }
    }

    @ViewBuilder
    private var deleteMappingAlertMessage: some View {
        if let mapping = mappingToDelete {
            Text("\(L10n.t("confirm_delete_msg"))「\(mapping.name)」\(L10n.t("confirm_delete_hint"))")
        } else {
            Text(L10n.t("confirm_delete_generic"))
        }
    }

    @ViewBuilder
    private var deleteProviderAlertButtons: some View {
        Button(L10n.t("cancel"), role: .cancel) {
            providerToDelete = nil
        }
        Button(L10n.t("delete"), role: .destructive) {
            if let provider = providerToDelete {
                configManager.deleteProvider(provider.id)
                try? keychain.delete(forKey: provider.id.uuidString)
                if selectedProviderId == provider.id {
                    selectedProviderId = nil
                }
            }
            providerToDelete = nil
        }
    }

    @ViewBuilder
    private var deleteProviderAlertMessage: some View {
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

    @ViewBuilder
    private var unsavedChangesAlertButtons: some View {
        Button(L10n.t("cancel"), role: .cancel) {
            pendingSelection = nil
        }
        Button(L10n.t("discard_changes"), role: .destructive) {
            if let newSelection = pendingSelection {
                currentHasChanges = false
                applySelection(newSelection)
                forceResetTrigger += 1
            }
            pendingSelection = nil
        }
        Button(L10n.t("save_and_switch")) {
            if let newSelection = pendingSelection {
                targetSelection = newSelection
                saveAndSwitchTrigger += 1
            }
            pendingSelection = nil
        }
    }

    // MARK: - Selection Management

    private var currentSelection: SelectionTarget? {
        if let pid = selectedProviderId {
            return .provider(pid)
        }
        if let mid = selectedMappingId {
            return .mapping(mid)
        }
        return nil
    }

    private func applySelection(_ target: SelectionTarget) {
        switch target {
        case .provider(let id):
            selectedProviderId = id
            selectedMappingId = nil
        case .mapping(let id):
            selectedMappingId = id
            selectedProviderId = nil
        }
    }

    private func deleteSelected() {
        if let pid = selectedProviderId,
           let provider = configManager.findProvider(for: pid) {
            providerToDelete = provider
            showDeleteProviderConfirmation = true
        } else if let mid = selectedMappingId,
                  let mapping = configManager.mappings.first(where: { $0.id == mid }) {
            mappingToDelete = mapping
            showDeleteConfirmation = true
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
                    if let newSelection = targetSelection {
                        applySelection(newSelection)
                        targetSelection = nil
                    }
                },
                forceResetTrigger: forceResetTrigger,
                saveTrigger: saveAndSwitchTrigger
            )
            .id(pid)
        } else if let mappingId = selectedMappingId,
                  configManager.mappings.contains(where: { $0.id == mappingId }) {
            MappingDetailView(
                configManager: configManager,
                mappingId: mappingId,
                keychain: keychain,
                onHasChangesChange: { hasChanges in
                    currentHasChanges = hasChanges
                },
                onSave: {
                    currentHasChanges = false
                    if let newSelection = targetSelection {
                        applySelection(newSelection)
                        targetSelection = nil
                    }
                },
                forceResetTrigger: forceResetTrigger,
                saveTrigger: saveAndSwitchTrigger
            )
            .id(mappingId)
        } else {
            emptyStateView
        }
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
            HStack(spacing: 16) {
                Button {
                    showNewProviderSheet = true
                } label: {
                    Label(L10n.t("create_provider"), systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showNewMappingSheet = true
                } label: {
                    Label(L10n.t("create_new_config"), systemImage: "plus.square")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Copy Mapping

    private func copyMapping(_ mapping: ModelMapping) {
        let newMapping = ModelMapping(
            name: mapping.name + " 副本",
            incomingModel: mapping.incomingModel,
            actualModel: mapping.actualModel,
            providerConfigId: mapping.providerConfigId,
            parameters: mapping.parameters,
            isEnabled: mapping.isEnabled
        )

        configManager.add(newMapping)
        selectedMappingId = newMapping.id
        selectedProviderId = nil
    }
}

struct NewMappingView: View {
    let configManager: ConfigManager
    let keychain: KeychainService
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var l10n = LocalizationManager.shared

    @State private var name = "New Config"
    @State private var incomingModel = ""
    @State private var actualModel = ""
    @State private var selectedProviderId: UUID?
    @State private var showNewProviderSheet = false

    // 参数设置
    @State private var temperature = ""
    @State private var maxTokens = ""
    @State private var topP = ""
    @State private var frequencyPenalty = ""
    @State private var presencePenalty = ""
    @State private var thinkingEnabled = false
    @State private var thinkingBudget = ""
    @State private var thinkingOverrideEnabled = false

    // 自定义字段
    @State private var customFields: [CustomField] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(L10n.t("new_model_mapping"))
                    .font(.headline)
                    .padding(.top, 8)

                basicInfoSection
                paramInjectionSection
                thinkingSection
                customParamsSection
                actionButtons
            }
            .padding()
        }
        .frame(width: 500, height: 700)
        .sheet(isPresented: $showNewProviderSheet) {
            NewProviderView(configManager: configManager, keychain: keychain) { newProvider in
                selectedProviderId = newProvider.id
            }
        }
    }

    @ViewBuilder
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("basic_info"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                HStack {
                    Text(L10n.t("config_name"))
                        .frame(width: 100, alignment: .trailing)
                    TextField(L10n.t("config_name_placeholder"), text: $name)
                }
                HStack {
                    Text(L10n.t("incoming_model"))
                        .frame(width: 100, alignment: .trailing)
                    TextField(L10n.t("incoming_model_placeholder"), text: $incomingModel)
                }
                HStack {
                    Text(L10n.t("actual_model"))
                        .frame(width: 100, alignment: .trailing)
                    TextField(L10n.t("actual_model_placeholder"), text: $actualModel)
                }
                HStack {
                    Text(L10n.t("provider"))
                        .frame(width: 100, alignment: .trailing)
                    Picker("", selection: $selectedProviderId) {
                        ForEach(configManager.providers) { provider in
                            Text(provider.name).tag(provider.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        showNewProviderSheet = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                }

                if let pid = selectedProviderId,
                   let provider = configManager.findProvider(for: pid) {
                    HStack {
                        Text("")
                            .frame(width: 100, alignment: .trailing)
                        Text("\(provider.apiProvider.rawValue) · \(provider.baseURL.host ?? provider.baseURL.absoluteString)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var paramInjectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("param_injection"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                HStack {
                    Text("Temperature")
                        .frame(width: 120, alignment: .trailing)
                    TextField(L10n.t("temp_placeholder"), text: $temperature)
                }
                HStack {
                    Text("Max Tokens")
                        .frame(width: 120, alignment: .trailing)
                    TextField(L10n.t("max_tokens_placeholder"), text: $maxTokens)
                }
                HStack {
                    Text("Top P")
                        .frame(width: 120, alignment: .trailing)
                    TextField(L10n.t("top_p_placeholder"), text: $topP)
                }
                HStack {
                    Text("Frequency Penalty")
                        .frame(width: 120, alignment: .trailing)
                    TextField(L10n.t("freq_penalty_placeholder"), text: $frequencyPenalty)
                }
                HStack {
                    Text("Presence Penalty")
                        .frame(width: 120, alignment: .trailing)
                    TextField(L10n.t("pres_penalty_placeholder"), text: $presencePenalty)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("reasoning_override"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $thinkingOverrideEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            VStack(spacing: 8) {
                HStack {
                    Toggle(L10n.t("enable_thinking"), isOn: $thinkingEnabled)
                        .disabled(!thinkingOverrideEnabled)
                    Spacer()
                }
                if thinkingEnabled,
                   let pid = selectedProviderId,
                   let provider = configManager.findProvider(for: pid),
                   provider.apiProvider == .anthropic {
                    HStack {
                        Text(L10n.t("thinking_budget"))
                            .frame(width: 120, alignment: .trailing)
                        TextField(L10n.t("thinking_budget_hint"), text: $thinkingBudget)
                            .disabled(!thinkingOverrideEnabled)
                        Text(L10n.t("thinking_budget_eg"))
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .opacity(thinkingOverrideEnabled ? 1.0 : 0.4)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var customParamsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("custom_params"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    customFields.append(CustomField(key: "", value: ""))
                }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
            }

            if customFields.isEmpty {
                Text(L10n.t("add_custom_hint"))
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(customFields.indices, id: \.self) { index in
                        HStack {
                            TextField(L10n.t("field_name_placeholder"), text: $customFields[index].key)
                                .frame(width: 120)
                            TextField(L10n.t("field_value_placeholder"), text: $customFields[index].value)
                            Button(action: {
                                customFields.remove(at: index)
                            }) {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text(L10n.t("custom_hint"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            Button(L10n.t("cancel")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(L10n.t("create")) {
                createMapping()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(incomingModel.isEmpty || actualModel.isEmpty || selectedProviderId == nil)
        }
        .padding(.bottom, 8)
    }

    private func createMapping() {
        guard let providerId = selectedProviderId else { return }

        let mapping = ModelMapping(
            name: name,
            incomingModel: incomingModel,
            actualModel: actualModel,
            providerConfigId: providerId,
            parameters: buildParameters()
        )

        configManager.add(mapping)
        dismiss()
    }

    private func buildParameters() -> InjectedParameters {
        let temp = Double(temperature)
        let tokens = Int(maxTokens)
        let topPValue = Double(topP)
        let freqPenalty = Double(frequencyPenalty)
        let presPenalty = Double(presencePenalty)

        let thinking: ThinkingConfig? = {
            guard thinkingOverrideEnabled else { return nil }
            return ThinkingConfig(
                enabled: thinkingEnabled,
                budgetTokens: thinkingEnabled ? Int(thinkingBudget) : nil
            )
        }()

        let customFieldsDict: [String: String]? = customFields.isEmpty
            ? nil
            : Dictionary(uniqueKeysWithValues: customFields.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) })

        return InjectedParameters(
            temperature: temp,
            maxTokens: tokens,
            topP: topPValue,
            frequencyPenalty: freqPenalty,
            presencePenalty: presPenalty,
            thinking: thinking,
            customFields: customFieldsDict
        )
    }
}
