import SwiftUI

struct MappingCardView: View {
    @ObservedObject var configManager: ConfigManager
    let keychain: KeychainService
    let mapping: ModelMapping

    @Binding var isExpanded: Bool
    var onSave: (() -> Void)?
    var onDelete: (() -> Void)?
    var onHasChangesChange: ((Bool) -> Void)?

    // 外部触发保存
    var externalSaveTrigger: Int = 0

    @ObservedObject private var l10n = LocalizationManager.shared

    @State private var showUnsavedAlert = false
    @State private var showDeleteConfirmation = false
    @State private var showDuplicateModelAlert = false
    @State private var focusIncomingModelTrigger = 0
    @State private var lastExternalSaveTrigger = 0

    // Form state
    @State private var name: String = ""
    @State private var incomingModel: String = ""
    @State private var actualModel: String = ""
    @State private var selectedProviderId: UUID?
    @State private var isEnabled = true

    @State private var temperature = ""
    @State private var maxTokens = ""
    @State private var topP = ""
    @State private var frequencyPenalty = ""
    @State private var presencePenalty = ""
    @State private var thinkingEnabled = false
    @State private var thinkingBudget = ""
    @State private var thinkingOverrideEnabled = false

    @State private var customFields: [CustomField] = []
    @State private var customFieldsEnabled = false

    // Original state for change detection
    @State private var originalMapping: ModelMapping?

    private var hasChanges: Bool {
        guard let original = originalMapping else { return false }
        if name != original.name { return true }
        if incomingModel != original.incomingModel { return true }
        if actualModel != original.actualModel { return true }
        if selectedProviderId != original.providerConfigId { return true }
        if isEnabled != original.isEnabled { return true }

        let currentParams = buildParameters()
        if currentParams.temperature != original.parameters.temperature { return true }
        if currentParams.maxTokens != original.parameters.maxTokens { return true }
        if currentParams.topP != original.parameters.topP { return true }
        if currentParams.frequencyPenalty != original.parameters.frequencyPenalty { return true }
        if currentParams.presencePenalty != original.parameters.presencePenalty { return true }
        if currentParams.thinkingOverrideEnabled != original.parameters.thinkingOverrideEnabled { return true }
        if currentParams.customFieldsEnabled != original.parameters.customFieldsEnabled { return true }
        if currentParams.customFields != original.parameters.customFields { return true }

        if let currentThinking = currentParams.thinking,
           let originalThinking = original.parameters.thinking {
            if currentThinking.enabled != originalThinking.enabled { return true }
            if currentThinking.budgetTokens != originalThinking.budgetTokens { return true }
        } else if currentParams.thinking != nil || original.parameters.thinking != nil {
            return true
        }

        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            HStack(spacing: 12) {
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .frame(width: 36, height: 20)
                    .onChange(of: isEnabled) { _, newValue in
                        if originalMapping != nil {
                            Task { @MainActor in
                                quickSaveEnabled(newValue)
                            }
                        }
                    }

                Button(action: {
                    if isExpanded && hasChanges {
                        showUnsavedAlert = true
                    } else {
                        let newValue = !isExpanded
                        if newValue {
                            loadMappingData()
                        }
                        isExpanded = newValue
                    }
                }) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(mapping.isEnabled ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mapping.name)
                                .font(.body)
                            Text("\(mapping.incomingModel) → \(mapping.actualModel)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                MappingEditForm(
                    configManager: configManager,
                    keychain: keychain,
                    name: $name,
                    incomingModel: $incomingModel,
                    actualModel: $actualModel,
                    selectedProviderId: $selectedProviderId,
                    isEnabled: $isEnabled,
                    temperature: $temperature,
                    maxTokens: $maxTokens,
                    topP: $topP,
                    frequencyPenalty: $frequencyPenalty,
                    presencePenalty: $presencePenalty,
                    thinkingOverrideEnabled: $thinkingOverrideEnabled,
                    thinkingEnabled: $thinkingEnabled,
                    thinkingBudget: $thinkingBudget,
                    customFields: $customFields,
                    customFieldsEnabled: $customFieldsEnabled,
                    focusIncomingModelTrigger: focusIncomingModelTrigger
                )
                .padding(12)

                HStack {
                    Button(L10n.t("save")) {
                        saveChanges()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges)

                    Button(L10n.t("cancel")) {
                        if hasChanges {
                            showUnsavedAlert = true
                        } else {
                            isExpanded = false
                        }
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .alert(L10n.t("confirm_delete_mapping"), isPresented: $showDeleteConfirmation) {
                        Button(L10n.t("cancel"), role: .cancel) { }
                        Button(L10n.t("delete"), role: .destructive) {
                            onDelete?()
                        }
                    } message: {
                        Text(L10n.t("confirm_delete_generic"))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .alert(L10n.t("unsaved_changes"), isPresented: $showUnsavedAlert) {
            Button(L10n.t("save"), role: .none) {
                saveChanges()
                isExpanded = false
            }
            Button(L10n.t("discard_changes"), role: .destructive) {
                loadMappingData()
                isExpanded = false
            }
            Button(L10n.t("cancel"), role: .cancel) { }
        } message: {
            Text(L10n.t("unsaved_changes_msg"))
        }
        .alert(L10n.t("duplicate_model_title"), isPresented: $showDuplicateModelAlert) {
            Button(L10n.t("ok"), role: .cancel) { }
        } message: {
            Text(L10n.t("duplicate_model_msg"))
        }
        .onAppear {
            loadMappingData()
            // 延迟通知，确保状态已同步
            DispatchQueue.main.async {
                onHasChangesChange?(false)
            }
        }
        .onChange(of: mapping.id) { _, _ in
            // 当 mapping 改变时（例如新创建的映射出现在列表中），重新加载数据
            loadMappingData()
            DispatchQueue.main.async {
                onHasChangesChange?(false)
            }
        }
        .onChange(of: hasChanges) { _, newValue in
            onHasChangesChange?(newValue)
        }
        .onChange(of: externalSaveTrigger) { _, newValue in
            if newValue != lastExternalSaveTrigger && hasChanges {
                lastExternalSaveTrigger = newValue
                saveChanges()
            }
        }
    }

    private func loadMappingData() {
        guard let current = configManager.mappings.first(where: { $0.id == mapping.id }) else { return }

        name = current.name
        incomingModel = current.incomingModel
        actualModel = current.actualModel
        selectedProviderId = current.providerConfigId
        isEnabled = current.isEnabled

        temperature = current.parameters.temperature.map { String($0) } ?? ""
        maxTokens = current.parameters.maxTokens.map { String($0) } ?? ""
        topP = current.parameters.topP.map { String($0) } ?? ""
        frequencyPenalty = current.parameters.frequencyPenalty.map { String($0) } ?? ""
        presencePenalty = current.parameters.presencePenalty.map { String($0) } ?? ""

        if let thinking = current.parameters.thinking {
            thinkingEnabled = thinking.enabled
            thinkingBudget = thinking.budgetTokens.map { String($0) } ?? ""
        } else {
            thinkingEnabled = false
            thinkingBudget = ""
        }
        thinkingOverrideEnabled = current.parameters.thinkingOverrideEnabled ?? false
        if current.parameters.thinkingOverrideEnabled == nil && current.parameters.thinking != nil {
            thinkingOverrideEnabled = true
        }

        if let fields = current.parameters.customFields, !fields.isEmpty {
            customFields = fields.map { CustomField(key: $0.key, value: $0.value) }
        } else {
            customFields = []
        }
        customFieldsEnabled = current.parameters.customFieldsEnabled ?? false
        if current.parameters.customFieldsEnabled == nil && current.parameters.customFields != nil {
            customFieldsEnabled = true
        }

        originalMapping = current
    }

    private func quickSaveEnabled(_ enabled: Bool) {
        guard var current = configManager.mappings.first(where: { $0.id == mapping.id }) else { return }
        current.isEnabled = enabled
        configManager.update(current)
        onSave?()
    }

    private func saveChanges() {
        guard var current = configManager.mappings.first(where: { $0.id == mapping.id }),
              let providerId = selectedProviderId else { return }

        // Check for duplicate incoming model name (excluding current mapping)
        let duplicateExists = configManager.mappings.contains { other in
            other.id != mapping.id &&
            other.incomingModel.lowercased() == incomingModel.lowercased()
        }
        if duplicateExists {
            showDuplicateModelAlert = true
            focusIncomingModelTrigger += 1
            return
        }

        current.name = name
        current.incomingModel = incomingModel
        current.actualModel = actualModel
        current.providerConfigId = providerId
        current.isEnabled = isEnabled
        current.parameters = buildParameters()

        configManager.update(current)
        originalMapping = current
        onHasChangesChange?(false)
        onSave?()
    }

    private func buildParameters() -> InjectedParameters {
        let temp = Double(temperature)
        let tokens = Int(maxTokens)
        let topPValue = Double(topP)
        let freqPenalty = Double(frequencyPenalty)
        let presPenalty = Double(presencePenalty)

        let thinking = ThinkingConfig(
            enabled: thinkingEnabled,
            budgetTokens: thinkingEnabled ? Int(thinkingBudget) : nil
        )

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
            thinkingOverrideEnabled: thinkingOverrideEnabled,
            customFields: customFieldsDict,
            customFieldsEnabled: customFields.isEmpty ? nil : customFieldsEnabled
        )
    }
}
