import SwiftUI

struct ConfigWindow: View {
    @ObservedObject var configManager: ConfigManager
    @State private var selectedMappingId: UUID?
    @State private var showNewMappingSheet = false
    @State private var showDeleteConfirmation = false
    @State private var mappingToDelete: ModelMapping?

    // 变更追踪
    @State private var currentMappingHasChanges = false
    @State private var pendingSelectionId: UUID?
    @State private var targetSelectionId: UUID?  // 保存后要切换的目标
    @State private var showSwitchConfirmation = false
    @State private var forceResetTrigger = 0
    @State private var saveAndSwitchTrigger = 0

    @ObservedObject private var l10n = LocalizationManager.shared
    private let keychain = KeychainService.shared

    var body: some View {
        NavigationSplitView {
            VStack {
                MappingListView(
                    configManager: configManager,
                    selectedMappingId: Binding(
                        get: { selectedMappingId },
                        set: { newId in
                            if currentMappingHasChanges && newId != selectedMappingId {
                                pendingSelectionId = newId
                                showSwitchConfirmation = true
                            } else {
                                selectedMappingId = newId
                            }
                        }
                    ),
                    onCopy: { mapping in
                        copyMapping(mapping)
                    },
                    onDelete: { mapping in
                        mappingToDelete = mapping
                        showDeleteConfirmation = true
                    }
                )

                HStack {
                    Button {
                        showNewMappingSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help(L10n.t("add_mapping"))

                    Button {
                        guard let id = selectedMappingId,
                              let mapping = configManager.mappings.first(where: { $0.id == id }) else { return }
                        mappingToDelete = mapping
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help(L10n.t("delete_mapping"))
                    .disabled(selectedMappingId == nil)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle(L10n.t("model_mapping"))
            .alert(L10n.t("confirm_delete"), isPresented: $showDeleteConfirmation) {
                Button(L10n.t("cancel"), role: .cancel) {
                    mappingToDelete = nil
                }
                Button(L10n.t("delete"), role: .destructive) {
                    if let mapping = mappingToDelete {
                        configManager.delete(mapping.id)
                        try? keychain.delete(forKey: mapping.id.uuidString)
                        if selectedMappingId == mapping.id {
                            selectedMappingId = nil
                        }
                    }
                    mappingToDelete = nil
                }
            } message: {
                if let mapping = mappingToDelete {
                    Text("\(L10n.t("confirm_delete_msg"))「\(mapping.name)」\(L10n.t("confirm_delete_hint"))")
                } else {
                    Text(L10n.t("confirm_delete_generic"))
                }
            }
            .alert(L10n.t("unsaved_changes"), isPresented: $showSwitchConfirmation) {
                Button(L10n.t("cancel"), role: .cancel) {
                    pendingSelectionId = nil
                }
                Button(L10n.t("discard_changes"), role: .destructive) {
                    if let newId = pendingSelectionId {
                        currentMappingHasChanges = false
                        selectedMappingId = newId
                        forceResetTrigger += 1
                    }
                    pendingSelectionId = nil
                }
                Button(L10n.t("save_and_switch")) {
                    if let newId = pendingSelectionId {
                        targetSelectionId = newId
                        saveAndSwitchTrigger += 1
                    }
                    pendingSelectionId = nil
                }
            } message: {
                Text(L10n.t("unsaved_changes_msg"))
            }
        } detail: {
            if let mappingId = selectedMappingId {
                MappingDetailView(
                    configManager: configManager,
                    mappingId: mappingId,
                    keychain: keychain,
                    onHasChangesChange: { hasChanges in
                        currentMappingHasChanges = hasChanges
                    },
                    onSave: {
                        currentMappingHasChanges = false
                        if let newId = targetSelectionId {
                            selectedMappingId = newId
                            targetSelectionId = nil
                        }
                    },
                    forceResetTrigger: forceResetTrigger,
                    saveTrigger: saveAndSwitchTrigger
                )
                .id(mappingId)
            } else {
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
                        showNewMappingSheet = true
                    } label: {
                        Label(L10n.t("create_new_config"), systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .sheet(isPresented: $showNewMappingSheet) {
            NewMappingView(configManager: configManager, keychain: keychain)
        }
        .onAppear {
            let mappingIds = configManager.mappings.map { $0.id.uuidString }
            keychain.preloadKeys(for: mappingIds)
        }
    }

    private func copyMapping(_ mapping: ModelMapping) {
        // 创建新配置，复制所有属性但使用新的 id
        let newMapping = ModelMapping(
            name: mapping.name + " 副本",
            incomingModel: mapping.incomingModel,
            actualModel: mapping.actualModel,
            apiProvider: mapping.apiProvider,
            baseURL: mapping.baseURL,
            parameters: mapping.parameters,
            isEnabled: mapping.isEnabled
        )

        // 添加新配置
        configManager.add(newMapping)

        // 复制 API Key
        if let apiKey = try? keychain.retrieve(forKey: mapping.id.uuidString) {
            try? keychain.save(apiKey, forKey: newMapping.id.uuidString)
        }

        // 选中新配置
        selectedMappingId = newMapping.id
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
    @State private var apiProvider: APIProvider = .openai
    @State private var baseURL = ""
    @State private var apiKey = ""

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
                            Text(L10n.t("api_provider"))
                                .frame(width: 100, alignment: .trailing)
                            Picker("", selection: $apiProvider) {
                                Text("OpenAI").tag(APIProvider.openai)
                                Text("Anthropic").tag(APIProvider.anthropic)
                            }
                            .pickerStyle(.menu)
                            .onChange(of: apiProvider) { _, newValue in
                                baseURL = newValue.defaultBaseURL.absoluteString
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
                    }

                    VStack(spacing: 8) {
                        HStack {
                            Toggle(L10n.t("enable_thinking"), isOn: $thinkingEnabled)
                                .disabled(!thinkingOverrideEnabled)
                            Spacer()
                        }
                        if thinkingEnabled && apiProvider == .anthropic {
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

                // 自定义参数字段
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

                HStack {
                    Button(L10n.t("cancel")) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(L10n.t("create")) {
                        createMapping()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(incomingModel.isEmpty || actualModel.isEmpty || apiKey.isEmpty)
                }
                .padding(.bottom, 8)
            }
            .padding()
        }
        .frame(width: 500, height: 700)
        .onAppear {
            baseURL = apiProvider.defaultBaseURL.absoluteString
        }
    }

    private func createMapping() {
        let mapping = ModelMapping(
            name: name,
            incomingModel: incomingModel,
            actualModel: actualModel,
            apiProvider: apiProvider,
            baseURL: URL(string: baseURL) ?? apiProvider.defaultBaseURL,
            parameters: buildParameters()
        )

        configManager.add(mapping)
        try? keychain.save(apiKey, forKey: mapping.id.uuidString)
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
