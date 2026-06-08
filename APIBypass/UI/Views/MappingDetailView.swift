import SwiftUI

struct CustomField: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

struct MappingDetailView: View {
    @ObservedObject var configManager: ConfigManager
    let mappingId: UUID
    let keychain: KeychainService

    // 变更回调
    var onHasChangesChange: ((Bool) -> Void)?
    var onSave: (() -> Void)?
    var forceResetTrigger: Int = 0
    var saveTrigger: Int = 0

    private let l10n = LocalizationManager.shared

    @State private var name: String = ""
    @State private var incomingModel: String = ""
    @State private var actualModel: String = ""
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
    @State private var isEnabled = true

    // 自定义字段
    @State private var customFields: [CustomField] = []
    @State private var customFieldsEnabled = false

    @State private var showSaveConfirmation = false

    // 存储原始数据用于变更检测
    @State private var originalMapping: ModelMapping?
    @State private var originalProviderId: UUID?
    @State private var lastResetTrigger = 0
    @State private var lastSaveTrigger = 0

    // 变更检测
    private var hasChanges: Bool {
        guard let original = originalMapping else { return false }

        // 检查基本字段
        if name != original.name { return true }
        if incomingModel != original.incomingModel { return true }
        if actualModel != original.actualModel { return true }
        if selectedProviderId != original.providerConfigId { return true }
        if isEnabled != original.isEnabled { return true }

        // 检查参数
        let currentParams = buildParameters()
        if currentParams.temperature != original.parameters.temperature { return true }
        if currentParams.maxTokens != original.parameters.maxTokens { return true }
        if currentParams.topP != original.parameters.topP { return true }
        if currentParams.frequencyPenalty != original.parameters.frequencyPenalty { return true }
        if currentParams.presencePenalty != original.parameters.presencePenalty { return true }
        if currentParams.thinkingOverrideEnabled != original.parameters.thinkingOverrideEnabled { return true }
        if currentParams.customFieldsEnabled != original.parameters.customFieldsEnabled { return true }
        if currentParams.customFields != original.parameters.customFields { return true }

        // 检查 thinking
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
        ScrollView {
            VStack(spacing: 16) {
                // 启用状态
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "power")
                            .foregroundColor(isEnabled ? .green : .secondary)
                        Text(L10n.t("config_status"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Toggle("", isOn: $isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .fixedSize()
                    }
                    Text(isEnabled ? L10n.t("config_enabled") : L10n.t("config_disabled"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 基本信息
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
                            TextField(L10n.t("incoming_model_field"), text: $incomingModel)
                        }
                        HStack {
                            Text(L10n.t("actual_model"))
                                .frame(width: 100, alignment: .trailing)
                            TextField(L10n.t("actual_model_field"), text: $actualModel)
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offset(x: -8)

                            Button {
                                showNewProviderSheet = true
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.plain)
                        }

                        // 提供商无效警告
                        if let pid = selectedProviderId,
                           configManager.findProvider(for: pid) == nil {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(L10n.t("provider_deleted_warning"))
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .padding(.leading, 108)
                        }

                        // 显示当前提供商信息（只读）
                        if let pid = selectedProviderId,
                           let provider = configManager.findProvider(for: pid) {
                            HStack {
                                Text("")
                                    .frame(width: 100, alignment: .trailing)
                                Text("\(L10n.t(provider.apiProvider == .openai ? "provider_type_openai" : "provider_type_anthropic")) · \(provider.baseURL.host ?? provider.baseURL.absoluteString)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 思考模式
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.t("reasoning_override"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Toggle("", isOn: $thinkingOverrideEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .fixedSize()
                    }

                    Text(L10n.t("reasoning_hint"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        HStack {
                            Text(L10n.t("enable_thinking"))
                            Spacer()
                            Toggle("", isOn: $thinkingEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .fixedSize()
                                .disabled(!thinkingOverrideEnabled)
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

                // 参数注入
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("param_injection"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        HStack {
                            Text(L10n.t("param_temperature"))
                                .frame(width: 120, alignment: .trailing)
                            TextField(L10n.t("temp_placeholder"), text: $temperature)
                        }
                        HStack {
                            Text(L10n.t("param_max_tokens"))
                                .frame(width: 120, alignment: .trailing)
                            TextField(L10n.t("max_tokens_placeholder"), text: $maxTokens)
                        }
                        HStack {
                            Text(L10n.t("param_top_p"))
                                .frame(width: 120, alignment: .trailing)
                            TextField(L10n.t("top_p_placeholder"), text: $topP)
                        }
                        HStack {
                            Text(L10n.t("param_frequency_penalty"))
                                .frame(width: 120, alignment: .trailing)
                            TextField(L10n.t("freq_penalty_placeholder"), text: $frequencyPenalty)
                        }
                        HStack {
                            Text(L10n.t("param_presence_penalty"))
                                .frame(width: 120, alignment: .trailing)
                            TextField(L10n.t("pres_penalty_placeholder"), text: $presencePenalty)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 自定义参数字段
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.t("custom_params"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Toggle("", isOn: $customFieldsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .fixedSize()
                    }

                    VStack(spacing: 8) {
                        HStack {
                            Button(action: {
                                customFields.append(CustomField(key: "", value: ""))
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle")
                                    Text(L10n.t("add_field"))
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!customFieldsEnabled)
                            Spacer()
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
                                            .frame(idealWidth: 140, maxWidth: .infinity)
                                            .disabled(!customFieldsEnabled)
                                        TextField(L10n.t("field_value_placeholder"), text: $customFields[index].value)
                                            .frame(idealWidth: 210, maxWidth: .infinity)
                                            .disabled(!customFieldsEnabled)
                                        Button(action: {
                                            customFields.remove(at: index)
                                        }) {
                                            Image(systemName: "minus.circle")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(!customFieldsEnabled)
                                    }
                                }
                            }
                        }
                    }
                    .opacity(customFieldsEnabled ? 1.0 : 0.4)

                    Text(L10n.t("custom_hint"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

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
            loadMappingData()
        }
        .onChange(of: hasChanges) { _, newValue in
            onHasChangesChange?(newValue)
        }
        .onChange(of: forceResetTrigger) { _, newValue in
            if newValue != lastResetTrigger {
                lastResetTrigger = newValue
                loadMappingData()
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
        .sheet(isPresented: $showNewProviderSheet) {
            NewProviderView(configManager: configManager, keychain: keychain) { newProvider in
                selectedProviderId = newProvider.id
            }
        }
    }

    private func loadMappingData() {
        guard let mapping = configManager.mappings.first(where: { $0.id == mappingId }) else { return }

        name = mapping.name
        incomingModel = mapping.incomingModel
        actualModel = mapping.actualModel
        selectedProviderId = mapping.providerConfigId
        isEnabled = mapping.isEnabled

        if let temp = mapping.parameters.temperature {
            temperature = String(temp)
        }
        if let tokens = mapping.parameters.maxTokens {
            maxTokens = String(tokens)
        }
        if let topPValue = mapping.parameters.topP {
            topP = String(topPValue)
        }
        if let freq = mapping.parameters.frequencyPenalty {
            frequencyPenalty = String(freq)
        }
        if let pres = mapping.parameters.presencePenalty {
            presencePenalty = String(pres)
        }
        if let thinking = mapping.parameters.thinking {
            thinkingEnabled = thinking.enabled
            if let budget = thinking.budgetTokens {
                thinkingBudget = String(budget)
            }
        } else {
            thinkingEnabled = false
            thinkingBudget = ""
        }
        if let enabled = mapping.parameters.thinkingOverrideEnabled {
            thinkingOverrideEnabled = enabled
        }
        // 兼容旧数据：没有 thinkingOverrideEnabled 字段但有 thinking 数据时，默认开启
        if mapping.parameters.thinkingOverrideEnabled == nil && mapping.parameters.thinking != nil {
            thinkingOverrideEnabled = true
        }

        if let fields = mapping.parameters.customFields, !fields.isEmpty {
            customFields = fields.map { CustomField(key: $0.key, value: $0.value) }
        }
        if let enabled = mapping.parameters.customFieldsEnabled {
            customFieldsEnabled = enabled
        } else if mapping.parameters.customFields != nil {
            // 兼容旧数据：没有 customFieldsEnabled 字段但有数据时，默认开启
            customFieldsEnabled = true
        }

        loadOriginalData()
    }

    private func loadOriginalData() {
        originalMapping = configManager.mappings.first(where: { $0.id == mappingId })
        originalProviderId = selectedProviderId
        onHasChangesChange?(false)
    }

    private func saveChanges() {
        guard let mapping = configManager.mappings.first(where: { $0.id == mappingId }),
              let providerId = selectedProviderId else { return }

        let updatedMapping = ModelMapping(
            id: mapping.id,
            name: name,
            incomingModel: incomingModel,
            actualModel: actualModel,
            providerConfigId: providerId,
            parameters: buildParameters(),
            isEnabled: isEnabled
        )

        configManager.update(updatedMapping)
        onSave?()
        showSaveConfirmation = true
    }

    private func buildParameters() -> InjectedParameters {
        let temp = Double(temperature)
        let tokens = Int(maxTokens)
        let topPValue = Double(topP)
        let freqPenalty = Double(frequencyPenalty)
        let presPenalty = Double(presencePenalty)

        // 始终保存思考配置数据（即使开关关闭），以便下次开启时恢复
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

    /// 重置为原始数据（放弃变更）
    func discardChanges() {
        loadMappingData()
    }
}
