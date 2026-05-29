import SwiftUI

struct LaunchClaudeCodeView: View {
    @ObservedObject var configManager: ConfigManager
    @Environment(\.dismiss) private var dismiss

    // 持久化设置
    @AppStorage("launcher.selectedProviderId") private var savedProviderId: String?
    @AppStorage("launcher.selectedTerminalId") private var savedTerminalId: String = "terminal"
    @AppStorage("launcher.workingDirectory") private var savedWorkingDirectory: String = ""
    @AppStorage("launcher.anthropicModel") private var savedAnthropicModel: String = ""
    @AppStorage("launcher.opusModel") private var savedOpusModel: String = ""
    @AppStorage("launcher.sonnetModel") private var savedSonnetModel: String = ""
    @AppStorage("launcher.haikuModel") private var savedHaikuModel: String = ""
    @AppStorage("launcher.subagentModel") private var savedSubagentModel: String = ""
    @AppStorage("launcher.effortLevel") private var savedEffortLevel: String = ""
    @AppStorage("launcher.disableAttributionHeader") private var savedDisableAttributionHeader: Bool = false
    @AppStorage("launcher.rectifierEnabled") private var savedRectifierEnabled: Bool = true
    @AppStorage("serverPort") private var serverPort: Int = 8390

    @State private var selectedProviderId: UUID?
    @State private var selectedTerminalId: String = "terminal"
    @State private var workingDirectory: String = ""
    @State private var showDirectoryPicker = false
    @State private var anthropicModel: String = ""
    @State private var opusModel: String = ""
    @State private var sonnetModel: String = ""
    @State private var haikuModel: String = ""
    @State private var subagentModel: String = ""
    @State private var effortLevel: String = ""
    @State private var disableAttributionHeader: Bool = false
    @State private var rectifierEnabled: Bool = true

    @State private var isLaunching = false
    @State private var errorMessage: String?

    private var availableTerminals: [TerminalApp] {
        ClaudeCodeLauncher.availableTerminals()
    }

    private var selectedTerminal: TerminalApp? {
        availableTerminals.first { $0.id == selectedTerminalId }
    }

    private var selectedProvider: ProviderConfig? {
        guard let id = selectedProviderId else { return nil }
        return configManager.findProvider(for: id)
    }

    private var localBaseURL: String {
        "http://127.0.0.1:\(serverPort)"
    }

    private var canLaunch: Bool {
        guard selectedProvider != nil,
              !anthropicModel.isEmpty,
              selectedTerminal != nil else {
            return false
        }
        return true
    }

    var body: some View {
        VStack(spacing: 20) {
            // 标题
            headerView

            ScrollView {
                VStack(spacing: 20) {
                    // 提供商、终端、目录选择
                    selectionSection

                    if let provider = selectedProvider {
                        Divider()
                            .padding(.vertical, 4)

                        // 环境变量配置
                        envVarsSection(provider: provider)
                    }
                }
                .padding(.horizontal, 4)
            }

            // 错误信息
            if let error = errorMessage {
                errorView(message: error)
            }

            // 底部按钮
            buttonBar
        }
        .padding(24)
        .frame(minWidth: 700, idealWidth: 750, minHeight: 720, idealHeight: 800)
        .onAppear {
            loadSavedSettings()
        }
        .fileImporter(
            isPresented: $showDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    workingDirectory = url.path
                    saveSettings()
                }
            case .failure:
                break
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 28))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("launch_claude_code"))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(L10n.t("launch_claude_code_desc"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Selection Section

    private var selectionSection: some View {
        VStack(spacing: 16) {
            // 提供商选择
            HStack(spacing: 16) {
                Text(L10n.t("select_provider"))
                    .font(.headline)
                    .frame(width: 100, alignment: .leading)

                Picker("", selection: $selectedProviderId) {
                    Text(L10n.t("please_select")).tag(UUID?.none)
                    ForEach(configManager.providers) { provider in
                        Text(provider.name).tag(provider.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .onChange(of: selectedProviderId) { _, _ in saveSettings() }

                Spacer()
            }

            // 终端选择
            HStack(spacing: 16) {
                Text(L10n.t("select_terminal"))
                    .font(.headline)
                    .frame(width: 100, alignment: .leading)

                Picker("", selection: $selectedTerminalId) {
                    ForEach(availableTerminals) { terminal in
                        Text(terminal.name).tag(terminal.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .onChange(of: selectedTerminalId) { _, _ in saveSettings() }

                Spacer()
            }

            // 工作目录选择
            HStack(spacing: 16) {
                Text(L10n.t("working_directory"))
                    .font(.headline)
                    .frame(width: 100, alignment: .leading)

                TextField(L10n.t("working_directory_hint"), text: $workingDirectory)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: workingDirectory) { _, _ in saveSettings() }

                Button {
                    showDirectoryPicker = true
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Environment Variables Section

    private func envVarsSection(provider: ProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("claude_code_env_vars_title"))
                .font(.headline)

            // 只读环境变量 (基础配置)
            Group {
                envVarReadOnlyRow(
                    name: "ANTHROPIC_BASE_URL",
                    value: localBaseURL,
                    icon: "link"
                )

                envVarReadOnlyRow(
                    name: "ANTHROPIC_AUTH_TOKEN",
                    value: "1234 (placeholder)",
                    icon: "key.fill"
                )
            }

            Divider()

            // 可配置环境变量
            Text(L10n.t("model_settings"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            // ANTHROPIC_MODEL (必填)
            modelPickerRow(
                name: "ANTHROPIC_MODEL",
                selection: $anthropicModel,
                mappings: enabledMappings(provider: provider),
                isRequired: true
            )

            // 其他模型配置
            modelPickerRow(
                name: "ANTHROPIC_DEFAULT_OPUS_MODEL",
                selection: $opusModel,
                mappings: enabledMappings(provider: provider)
            )

            modelPickerRow(
                name: "ANTHROPIC_DEFAULT_SONNET_MODEL",
                selection: $sonnetModel,
                mappings: enabledMappings(provider: provider)
            )

            modelPickerRow(
                name: "ANTHROPIC_DEFAULT_HAIKU_MODEL",
                selection: $haikuModel,
                mappings: enabledMappings(provider: provider)
            )

            modelPickerRow(
                name: "CLAUDE_CODE_SUBAGENT_MODEL",
                selection: $subagentModel,
                mappings: enabledMappings(provider: provider)
            )

            // EFFORT_LEVEL
            HStack(spacing: 12) {
                Text("CLAUDE_CODE_EFFORT_LEVEL")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 280, alignment: .leading)

                Picker("", selection: $effortLevel) {
                    Text(L10n.t("none")).tag("")
                    Text("low").tag("low")
                    Text("medium").tag("medium")
                    Text("high").tag("high")
                    Text("max").tag("max")
                }
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: effortLevel) { _, _ in saveSettings() }

                Spacer()
            }

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("attribution_header"))
                        .font(.system(.body, design: .monospaced))
                    Text(L10n.t("attribution_header_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Text(L10n.t("attribution_header_note"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(width: 480, alignment: .leading)

                Toggle("", isOn: $disableAttributionHeader)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: disableAttributionHeader) { _, _ in saveSettings() }

                Spacer()
            }

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("rectifier"))
                        .font(.system(.body, design: .monospaced))
                    Text(L10n.t("rectifier_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                .frame(width: 480, alignment: .leading)

                Toggle("", isOn: $rectifierEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: rectifierEnabled) { _, _ in saveSettings() }

                Spacer()
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private func envVarReadOnlyRow(name: String, value: String, icon: String, isError: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(isError ? .red : .secondary)
                .frame(width: 16)

            Text(name)
                .font(.system(.body, design: .monospaced))
                .frame(width: 280, alignment: .leading)

            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(isError ? .red : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
    }

    private func modelPickerRow(name: String, selection: Binding<String>, mappings: [ModelMapping], isRequired: Bool = false) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(name)
                    .font(.system(.body, design: .monospaced))

                if isRequired {
                    Text("*")
                        .foregroundColor(.red)
                        .font(.body)
                }
            }
            .frame(width: 280, alignment: .leading)

            Picker("", selection: selection) {
                Text(isRequired ? L10n.t("please_select") : L10n.t("none")).tag("")
                ForEach(mappings, id: \.id) { mapping in
                    Text(mapping.incomingModel).tag(mapping.incomingModel)
                }
            }
            .labelsHidden()
            .frame(width: 200)
            .onChange(of: selection.wrappedValue) { _, _ in saveSettings() }

            Spacer()
        }
    }

    private func enabledMappings(provider: ProviderConfig) -> [ModelMapping] {
        configManager.mappingsForProvider(provider.id).filter { $0.isEnabled }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Button Bar

    private var buttonBar: some View {
        HStack {
            Button(L10n.t("cancel")) {
                dismiss()
            }
            .keyboardShortcut(.escape)

            Spacer()

            Button {
                launchClaudeCode()
            } label: {
                HStack(spacing: 6) {
                    if isLaunching {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(L10n.t("launch"))
                }
                .frame(minWidth: 80)
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .disabled(!canLaunch || isLaunching)
        }
    }

    // MARK: - Persistence

    private func loadSavedSettings() {
        // 恢复上次选择的提供商
        if let idString = savedProviderId,
           let id = UUID(uuidString: idString),
           configManager.findProvider(for: id) != nil {
            selectedProviderId = id
        }

        // 恢复终端选择
        if availableTerminals.contains(where: { $0.id == savedTerminalId }) {
            selectedTerminalId = savedTerminalId
        } else if let first = availableTerminals.first {
            selectedTerminalId = first.id
        }

        // 恢复工作目录
        workingDirectory = savedWorkingDirectory

        // 恢复上次的环境变量设置
        anthropicModel = savedAnthropicModel
        opusModel = savedOpusModel
        sonnetModel = savedSonnetModel
        haikuModel = savedHaikuModel
        subagentModel = savedSubagentModel
        effortLevel = savedEffortLevel
        disableAttributionHeader = savedDisableAttributionHeader
        rectifierEnabled = savedRectifierEnabled
    }

    private func saveSettings() {
        savedProviderId = selectedProviderId?.uuidString
        savedTerminalId = selectedTerminalId
        savedWorkingDirectory = workingDirectory
        savedAnthropicModel = anthropicModel
        savedOpusModel = opusModel
        savedSonnetModel = sonnetModel
        savedHaikuModel = haikuModel
        savedSubagentModel = subagentModel
        savedEffortLevel = effortLevel
        savedDisableAttributionHeader = disableAttributionHeader
        savedRectifierEnabled = rectifierEnabled
    }

    // MARK: - Launch

    private func launchClaudeCode() {
        guard let provider = selectedProvider,
              let terminal = selectedTerminal else {
            errorMessage = L10n.t("no_provider_selected")
            return
        }

        isLaunching = true
        errorMessage = nil

        // 构建环境变量
        var customEnvVars: [String: String] = [
            "ANTHROPIC_BASE_URL": localBaseURL,
            "ANTHROPIC_AUTH_TOKEN": "1234",
            "ANTHROPIC_MODEL": anthropicModel
        ]

        if !opusModel.isEmpty { customEnvVars["ANTHROPIC_DEFAULT_OPUS_MODEL"] = opusModel }
        if !sonnetModel.isEmpty { customEnvVars["ANTHROPIC_DEFAULT_SONNET_MODEL"] = sonnetModel }
        if !haikuModel.isEmpty { customEnvVars["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = haikuModel }
        if !subagentModel.isEmpty { customEnvVars["CLAUDE_CODE_SUBAGENT_MODEL"] = subagentModel }
        if !effortLevel.isEmpty { customEnvVars["CLAUDE_CODE_EFFORT_LEVEL"] = effortLevel }

        // 工作目录
        let workDir = workingDirectory.isEmpty ? nil : URL(fileURLWithPath: workingDirectory)

        let launcher = ClaudeCodeLauncher()
        let configuration = LaunchConfiguration(
            provider: provider,
            selectedMapping: nil,
            customEnvVars: customEnvVars,
            workingDirectory: workDir,
            disableAttributionHeader: disableAttributionHeader
        )

        do {
            try launcher.launchInTerminal(terminal: terminal, configuration: configuration)
            dismiss()
        } catch {
            isLaunching = false
            errorMessage = error.localizedDescription
        }
    }
}
