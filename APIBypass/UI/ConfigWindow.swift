import SwiftUI

struct ConfigWindow: View {
    @StateObject private var configManager = ConfigManager()
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

    var body: some View {
        VStack(spacing: 20) {
            Text("新建模型映射")
                .font(.headline)

            Form {
                TextField("配置名称", text: $name)
                TextField("客户端模型名", text: $incomingModel)
                TextField("实际模型名", text: $actualModel)
                Picker("API 提供商", selection: $apiProvider) {
                    Text("OpenAI").tag(APIProvider.openai)
                    Text("Anthropic").tag(APIProvider.anthropic)
                }
                TextField("API 地址", text: $baseURL)
                SecureField("API Key", text: $apiKey)
            }
            .formStyle(.grouped)

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
        }
        .frame(width: 400, height: 350)
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
            parameters: .empty
        )

        configManager.add(mapping)
        try? keychain.save(apiKey, forKey: mapping.id.uuidString)
        dismiss()
    }
}
