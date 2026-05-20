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

    @State private var name: String = ""
    @State private var incomingModel: String = ""
    @State private var actualModel: String = ""
    @State private var apiProvider: APIProvider = .openai
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""

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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 基本信息
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
                            TextField("请求的模型名", text: $incomingModel)
                        }
                        HStack {
                            Text("实际模型名")
                                .frame(width: 100, alignment: .trailing)
                            TextField("实际调用的模型", text: $actualModel)
                        }
                        HStack {
                            Text("API接口类型")
                                .frame(width: 100, alignment: .trailing)
                            Picker("", selection: $apiProvider) {
                                Text("OpenAI").tag(APIProvider.openai)
                                Text("Anthropic").tag(APIProvider.anthropic)
                            }
                            .pickerStyle(.menu)
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

                // 思考模式
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("更改默认推理模式")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Toggle("", isOn: $thinkingOverrideEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    Text("通过 enable_thinking 参数控制思考模式")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        HStack {
                            Text("是否启用思考模式")
                            Spacer()
                            Toggle("", isOn: $thinkingEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .disabled(!thinkingOverrideEnabled)
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

                // 参数注入
                VStack(alignment: .leading, spacing: 12) {
                    Text("参数注入")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        HStack {
                            Text("Temperature")
                                .frame(width: 120, alignment: .trailing)
                            TextField("0.0 - 2.0", text: $temperature)
                            Text("创造性程度")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        HStack {
                            Text("Max Tokens")
                                .frame(width: 120, alignment: .trailing)
                            TextField("最大输出长度", text: $maxTokens)
                            Text("最大输出")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        HStack {
                            Text("Top P")
                                .frame(width: 120, alignment: .trailing)
                            TextField("0.0 - 1.0", text: $topP)
                            Text("核采样")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        HStack {
                            Text("Frequency Penalty")
                                .frame(width: 120, alignment: .trailing)
                            TextField("-2.0 - 2.0", text: $frequencyPenalty)
                            Text("频率惩罚")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        HStack {
                            Text("Presence Penalty")
                                .frame(width: 120, alignment: .trailing)
                            TextField("-2.0 - 2.0", text: $presencePenalty)
                            Text("存在惩罚")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
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
                        Toggle("", isOn: $customFieldsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    VStack(spacing: 8) {
                        HStack {
                            Button(action: {
                                customFields.append(CustomField(key: "", value: ""))
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle")
                                    Text("添加字段")
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!customFieldsEnabled)
                            Spacer()
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
                                            .frame(idealWidth: 140, maxWidth: .infinity)
                                            .disabled(!customFieldsEnabled)
                                        TextField("值 (JSON格式)", text: $customFields[index].value)
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

                    Text("提示: 值支持 JSON 格式，如 \"enable_thinking\":true, \"thinking\": {\"type\": \"disabled\"}")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 启用状态
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Toggle("启用此配置", isOn: $isEnabled)
                        Spacer()
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

            }
            .padding()
        }
        .toolbar {
            Button("保存") {
                saveChanges()
            }
            .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            loadMappingData()
        }
        .alert("已保存", isPresented: $showSaveConfirmation) {
            Button("好的", role: .cancel) { }
        }
    }

    private func loadMappingData() {
        guard let mapping = configManager.mappings.first(where: { $0.id == mappingId }) else { return }

        name = mapping.name
        incomingModel = mapping.incomingModel
        actualModel = mapping.actualModel
        apiProvider = mapping.apiProvider
        baseURL = mapping.baseURL.absoluteString
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

        if let key = try? keychain.retrieve(forKey: mappingId.uuidString) {
            apiKey = key
        }
    }

    private func saveChanges() {
        guard let mapping = configManager.mappings.first(where: { $0.id == mappingId }) else { return }

        let updatedMapping = ModelMapping(
            id: mapping.id,
            name: name,
            incomingModel: incomingModel,
            actualModel: actualModel,
            apiProvider: apiProvider,
            baseURL: URL(string: baseURL) ?? apiProvider.defaultBaseURL,
            parameters: buildParameters(),
            isEnabled: isEnabled
        )

        configManager.update(updatedMapping)

        if !apiKey.isEmpty {
            try? keychain.save(apiKey, forKey: mappingId.uuidString)
        }

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
}
