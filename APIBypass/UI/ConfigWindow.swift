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
    @State private var forceResetTrigger = 0  // 用于触发重置（放弃更改）
    @State private var saveAndSwitchTrigger = 0  // 用于触发保存并切换

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
                    .help("添加映射")

                    Button {
                        guard let id = selectedMappingId,
                              let mapping = configManager.mappings.first(where: { $0.id == id }) else { return }
                        mappingToDelete = mapping
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("删除映射")
                    .disabled(selectedMappingId == nil)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("模型映射")
            .alert("确认删除", isPresented: $showDeleteConfirmation) {
                Button("取消", role: .cancel) {
                    mappingToDelete = nil
                }
                Button("删除", role: .destructive) {
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
                    Text("确定要删除配置「\(mapping.name)」吗？此操作无法撤销。")
                } else {
                    Text("确定要删除此配置吗？")
                }
            }
            .alert("未保存的更改", isPresented: $showSwitchConfirmation) {
                Button("取消", role: .cancel) {
                    pendingSelectionId = nil
                }
                Button("放弃更改", role: .destructive) {
                    if let newId = pendingSelectionId {
                        currentMappingHasChanges = false
                        selectedMappingId = newId
                        forceResetTrigger += 1
                    }
                    pendingSelectionId = nil
                }
                Button("保存并切换") {
                    if let newId = pendingSelectionId {
                        targetSelectionId = newId  // 保存目标 ID
                        saveAndSwitchTrigger += 1
                    }
                    pendingSelectionId = nil
                }
            } message: {
                Text("当前配置有未保存的更改，是否保存？")
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
                        // 如果有待切换的配置，执行切换
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
                    Text("选择或创建配置")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("从左侧列表选择一个配置进行编辑，或点击 + 按钮创建新配置")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        showNewMappingSheet = true
                    } label: {
                        Label("创建新配置", systemImage: "plus.circle")
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
            // 预加载所有 API Keys 到缓存，避免后续授权提示
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

    @State private var name = "新配置"
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
                Text("新建模型映射")
                    .font(.headline)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("基本信息")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        HStack {
                            Text("配置名称")
                                .frame(width: 100, alignment: .trailing)
                            TextField("名称", text: $name)
                        }
                        HStack {
                            Text("客户端模型名")
                                .frame(width: 100, alignment: .trailing)
                            TextField("如 gpt-4", text: $incomingModel)
                        }
                        HStack {
                            Text("实际模型名")
                                .frame(width: 100, alignment: .trailing)
                            TextField("如 claude-sonnet-4-6", text: $actualModel)
                        }
                        HStack {
                            Text("API接口类型")
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
                            Text("Base URL")
                                .frame(width: 100, alignment: .trailing)
                            TextField("Base URL", text: $baseURL)
                        }
                        HStack {
                            Text("API Key")
                                .frame(width: 100, alignment: .trailing)
                            SecureField("sk-...", text: $apiKey)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("参数注入")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        HStack {
                            Text("Temperature")
                                .frame(width: 120, alignment: .trailing)
                            TextField("0.0 - 2.0，创造性程度", text: $temperature)
                        }
                        HStack {
                            Text("Max Tokens")
                                .frame(width: 120, alignment: .trailing)
                            TextField("最大输出长度", text: $maxTokens)
                        }
                        HStack {
                            Text("Top P")
                                .frame(width: 120, alignment: .trailing)
                            TextField("0.0 - 1.0，核采样", text: $topP)
                        }
                        HStack {
                            Text("Frequency Penalty")
                                .frame(width: 120, alignment: .trailing)
                            TextField("-2.0 - 2.0，频率惩罚", text: $frequencyPenalty)
                        }
                        HStack {
                            Text("Presence Penalty")
                                .frame(width: 120, alignment: .trailing)
                            TextField("-2.0 - 2.0，存在惩罚", text: $presencePenalty)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 思考模式
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("思考模式")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Toggle("", isOn: $thinkingOverrideEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    VStack(spacing: 8) {
                        HStack {
                            Toggle("启用思考模式", isOn: $thinkingEnabled)
                                .disabled(!thinkingOverrideEnabled)
                            Spacer()
                        }
                        if thinkingEnabled && apiProvider == .anthropic {
                            HStack {
                                Text("思考预算")
                                    .frame(width: 120, alignment: .trailing)
                                TextField("tokens 数量", text: $thinkingBudget)
                                    .disabled(!thinkingOverrideEnabled)
                                Text("如 10000")
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
                        Text("自定义参数")
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
                        Text("添加自定义 JSON 参数字段")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(customFields.indices, id: \.self) { index in
                                HStack {
                                    TextField("字段名", text: $customFields[index].key)
                                        .frame(width: 120)
                                    TextField("值 (JSON格式)", text: $customFields[index].value)
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

                    Text("提示: 值支持 JSON 格式，如 \"enable_thinking\":true, \"thinking\": {\"type\": \"disabled\"}")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                HStack {
                    Button("取消") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("创建") {
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
