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
    @State private var thinkingOverride = false
    @State private var isEnabled = true

    // 自定义字段
    @State private var customFields: [CustomField] = []

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
                            Text("API 提供商")
                                .frame(width: 100, alignment: .trailing)
                            Picker("", selection: $apiProvider) {
                                Text("OpenAI").tag(APIProvider.openai)
                                Text("Anthropic").tag(APIProvider.anthropic)
                            }
                            .pickerStyle(.menu)
                        }
                        HStack {
                            Text("API 地址")
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

                // 思考模式
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("思考模式")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Toggle("", isOn: $thinkingOverride)
                            .labelsHidden()
                    }

                    Toggle("启用思考模式", isOn: $thinkingEnabled)
                        .disabled(!thinkingOverride)

                    if thinkingEnabled && thinkingOverride && apiProvider == .anthropic {
                        HStack {
                            Text("思考预算")
                                .frame(width: 120, alignment: .trailing)
                            TextField("tokens 数量", text: $thinkingBudget)
                            Text("如 10000")
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

                    Text("提示: 值支持 JSON 格式，如 \"low\"、123、true、{\"key\": \"value\"}")
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

                // 保存按钮
                Button("保存配置") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
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
            thinkingOverride = true
            thinkingEnabled = thinking.enabled
            if let budget = thinking.budgetTokens {
                thinkingBudget = String(budget)
            }
        }

        if let fields = mapping.parameters.customFields {
            customFields = fields.map { CustomField(key: $0.key, value: $0.value) }
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

        let thinking: ThinkingConfig? = {
            guard thinkingOverride else { return nil }
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
