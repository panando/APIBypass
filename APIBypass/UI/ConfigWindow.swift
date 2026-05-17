import SwiftUI

struct ConfigWindow: View {
    @ObservedObject var configManager: ConfigManager
    @State private var selectedMappingId: UUID?
    @State private var showNewMappingSheet = false

    private let keychain = KeychainService()

    var body: some View {
        NavigationSplitView {
            VStack {
                MappingListView(
                    configManager: configManager,
                    selectedMappingId: $selectedMappingId
                )

                HStack {
                    Button {
                        showNewMappingSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("添加映射")

                    Button {
                        guard let id = selectedMappingId else { return }
                        configManager.delete(id)
                        selectedMappingId = nil
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
        } detail: {
            if let mappingId = selectedMappingId {
                MappingDetailView(
                    configManager: configManager,
                    mappingId: mappingId,
                    keychain: keychain
                )
            } else {
                Text("选择一个映射配置")
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showNewMappingSheet) {
            NewMappingView(configManager: configManager, keychain: keychain)
        }
    }
}

struct NewMappingView: View {
    let configManager: ConfigManager
    let keychain: KeychainService
    @Environment(\.dismiss) var dismiss

    @State private var name = "新配置"
    @State private var incomingModel = ""
    @State private var actualModel = ""
    @State private var apiProvider: APIProvider = .anthropic
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
    @State private var hasThinkingConfig = false

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
                            Text("API 提供商")
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
                    Text("思考模式")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Toggle("覆盖默认思考模式", isOn: $hasThinkingConfig)

                    if hasThinkingConfig {
                        VStack(spacing: 8) {
                            HStack {
                                Toggle("启用思考模式", isOn: $thinkingEnabled)
                                Spacer()
                            }
                            if thinkingEnabled && apiProvider == .anthropic {
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
            guard hasThinkingConfig else { return nil }
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
