import SwiftUI

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
    @State private var temperature: String = ""
    @State private var maxTokens: String = ""
    @State private var thinkingEnabled: Bool = false
    @State private var thinkingBudget: String = ""
    @State private var isEnabled: Bool = true

    @State private var showSaveConfirmation: Bool = false

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("配置名称", text: $name)
                TextField("客户端模型名", text: $incomingModel)
                    .help("客户端请求时使用的模型名")
                TextField("实际模型名", text: $actualModel)
                    .help("实际调用的上游模型")
                Picker("API 提供商", selection: $apiProvider) {
                    Text("OpenAI").tag(APIProvider.openai)
                    Text("Anthropic").tag(APIProvider.anthropic)
                }
                TextField("API 地址", text: $baseURL)
                    .help("如: https://api.anthropic.com")
                SecureField("API Key", text: $apiKey)
            }

            Section("参数注入") {
                HStack {
                    TextField("Temperature", text: $temperature)
                        .frame(width: 100)
                    Spacer()
                    Text("创造性程度 0-2")
                        .foregroundColor(.secondary)
                }
                HStack {
                    TextField("Max Tokens", text: $maxTokens)
                        .frame(width: 100)
                    Spacer()
                    Text("最大输出长度")
                        .foregroundColor(.secondary)
                }
            }

            if apiProvider == .anthropic {
                Section("思考模式 (Anthropic)") {
                    Toggle("启用思考", isOn: $thinkingEnabled)
                    if thinkingEnabled {
                        HStack {
                            TextField("思考预算 (tokens)", text: $thinkingBudget)
                                .frame(width: 150)
                            Spacer()
                            Text("如: 10000")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section {
                Toggle("启用此配置", isOn: $isEnabled)
            }
        }
        .formStyle(.grouped)
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
        if let thinking = mapping.parameters.thinking {
            thinkingEnabled = thinking.enabled
            if let budget = thinking.budgetTokens {
                thinkingBudget = String(budget)
            }
        }

        // 加载 API Key
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

        // 保存 API Key
        if !apiKey.isEmpty {
            try? keychain.save(apiKey, forKey: mappingId.uuidString)
        }

        showSaveConfirmation = true
    }

    private func buildParameters() -> InjectedParameters {
        let temp = Double(temperature)
        let tokens = Int(maxTokens)
        let thinking: ThinkingConfig? = thinkingEnabled
            ? ThinkingConfig(enabled: true, budgetTokens: Int(thinkingBudget))
            : nil

        return InjectedParameters(
            temperature: temp,
            maxTokens: tokens,
            thinking: thinking
        )
    }
}
