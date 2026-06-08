import SwiftUI

extension Notification.Name {
    static let launchClaudeCodeWindowDidShow = Notification.Name("launchClaudeCodeWindowDidShow")
}

struct LaunchClaudeCodeView: View {
    @ObservedObject var configManager: ConfigManager
    @Environment(\.dismiss) private var dismiss

    // 持久化设置

    @AppStorage("launcher.selectedTerminalId") private var savedTerminalId: String = "terminal"
    @AppStorage("launcher.workingDirectory") private var savedWorkingDirectory: String = ""
    @AppStorage("launcher.anthropicModel") private var savedAnthropicModel: String = ""
    @AppStorage("launcher.anthropicModelProviderId") private var savedAnthropicModelProviderId: String?
    @AppStorage("launcher.opusModel") private var savedOpusModel: String = ""
    @AppStorage("launcher.opusModelProviderId") private var savedOpusModelProviderId: String?
    @AppStorage("launcher.sonnetModel") private var savedSonnetModel: String = ""
    @AppStorage("launcher.sonnetModelProviderId") private var savedSonnetModelProviderId: String?
    @AppStorage("launcher.haikuModel") private var savedHaikuModel: String = ""
    @AppStorage("launcher.haikuModelProviderId") private var savedHaikuModelProviderId: String?
    @AppStorage("launcher.subagentModel") private var savedSubagentModel: String = ""
    @AppStorage("launcher.subagentModelProviderId") private var savedSubagentModelProviderId: String?
    @AppStorage("launcher.effortLevel") private var savedEffortLevel: String = ""
    @AppStorage("launcher.disableAttributionHeader") private var savedDisableAttributionHeader: Bool = false
    @AppStorage("launcher.rectifierEnabled") private var savedRectifierEnabled: Bool = true
    @AppStorage("serverPort") private var serverPort: Int = 8390

    @State private var selectedTerminalId: String = "terminal"
    @State private var workingDirectory: String = ""
    @State private var showDirectoryPicker = false
    @State private var effortLevel: String = ""
    @State private var disableAttributionHeader: Bool = false
    @State private var rectifierEnabled: Bool = true
    @State private var recentDirectories: [String] = []
    @State private var templates: [LaunchTemplate] = []
    @State private var activeTemplateName: String? = nil
    @State private var isTemplateDirty: Bool = false
    @State private var isApplyingTemplate: Bool = false
    @State private var showSaveTemplateSheet = false
    @State private var showRenameTemplateSheet = false
    @State private var showDeleteTemplateConfirm = false
    @State private var newTemplateName = ""
    @State private var renameText = ""
    @State private var showTerminalRunningAlert = false
    @State private var pendingTerminal: TerminalApp?

    @State private var isLaunching = false
    @State private var errorMessage: String?

    private var availableTerminals: [TerminalApp] {
        ClaudeCodeLauncher.availableTerminals()
    }

    private var selectedTerminal: TerminalApp? {
        availableTerminals.first { $0.id == selectedTerminalId }
    }

    private var localBaseURL: String {
        "http://127.0.0.1:\(serverPort)"
    }

    private var anthropicModelProviderBinding: Binding<UUID?> {
        Binding(
            get: {
                guard let idString = savedAnthropicModelProviderId,
                      let id = UUID(uuidString: idString),
                      configManager.providers.contains(where: { $0.id == id }) else {
                    return nil
                }
                return id
            },
            set: { savedAnthropicModelProviderId = $0?.uuidString }
        )
    }

    private var opusModelProviderBinding: Binding<UUID?> {
        Binding(
            get: {
                guard let idString = savedOpusModelProviderId,
                      let id = UUID(uuidString: idString),
                      configManager.providers.contains(where: { $0.id == id }) else {
                    return nil
                }
                return id
            },
            set: { savedOpusModelProviderId = $0?.uuidString }
        )
    }

    private var sonnetModelProviderBinding: Binding<UUID?> {
        Binding(
            get: {
                guard let idString = savedSonnetModelProviderId,
                      let id = UUID(uuidString: idString),
                      configManager.providers.contains(where: { $0.id == id }) else {
                    return nil
                }
                return id
            },
            set: { savedSonnetModelProviderId = $0?.uuidString }
        )
    }

    private var haikuModelProviderBinding: Binding<UUID?> {
        Binding(
            get: {
                guard let idString = savedHaikuModelProviderId,
                      let id = UUID(uuidString: idString),
                      configManager.providers.contains(where: { $0.id == id }) else {
                    return nil
                }
                return id
            },
            set: { savedHaikuModelProviderId = $0?.uuidString }
        )
    }

    private var subagentModelProviderBinding: Binding<UUID?> {
        Binding(
            get: {
                guard let idString = savedSubagentModelProviderId,
                      let id = UUID(uuidString: idString),
                      configManager.providers.contains(where: { $0.id == id }) else {
                    return nil
                }
                return id
            },
            set: { savedSubagentModelProviderId = $0?.uuidString }
        )
    }

    private var canLaunch: Bool {
        guard anthropicModelProviderBinding.wrappedValue != nil,
              !savedAnthropicModel.isEmpty,
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
        VStack(alignment: .leading, spacing: 28) {
                    // 提供商、终端、目录选择
                    selectionSection

                    envVarsSection
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
        .onReceive(NotificationCenter.default.publisher(for: .launchClaudeCodeWindowDidShow)) { _ in
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
        .sheet(isPresented: $showSaveTemplateSheet) {
            VStack(spacing: 16) {
                Text(L10n.t("save_as_template"))
                    .font(.headline)
                TextField(L10n.t("template_name"), text: $newTemplateName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                HStack(spacing: 12) {
                    Button(L10n.t("cancel")) {
                        showSaveTemplateSheet = false
                    }
                    .keyboardShortcut(.escape)
                    Button(L10n.t("save")) {
                        let name = newTemplateName.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            templates.removeAll { $0.name == name }
                            saveCurrentAsTemplate(name: name)
                            activeTemplateName = name
                            UserDefaults.standard.set(name, forKey: "launcher.activeTemplateName")
                            showSaveTemplateSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTemplateName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return)
                }
            }
            .padding(24)
            .frame(width: 350, height: 150)
        }
        .sheet(isPresented: $showRenameTemplateSheet) {
            VStack(spacing: 16) {
                Text(L10n.t("rename_template"))
                    .font(.headline)
                TextField(L10n.t("template_name"), text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                HStack(spacing: 12) {
                    Button(L10n.t("cancel")) {
                        showRenameTemplateSheet = false
                    }
                    .keyboardShortcut(.escape)
                    Button(L10n.t("save")) {
                        let newName = renameText.trimmingCharacters(in: .whitespaces)
                        if !newName.isEmpty, let target = templates.first(where: { $0.name == activeTemplateName }) {
                            renameTemplate(target, to: newName)
                            showRenameTemplateSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return)
                }
            }
            .padding(24)
            .frame(width: 350, height: 150)
        }
        .alert(L10n.t("delete_template"), isPresented: $showDeleteTemplateConfirm) {
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("delete"), role: .destructive) {
                if let target = templates.first(where: { $0.name == activeTemplateName }) {
                    deleteTemplate(target)
                }
            }
        } message: {
            Text(L10n.format("delete_template_confirm", activeTemplateName ?? ""))
        }
        .alert(L10n.t("terminal_already_running"), isPresented: $showTerminalRunningAlert) {
            Button(L10n.t("new_tab")) {
                if let terminal = pendingTerminal,
                   let providerId = anthropicModelProviderBinding.wrappedValue,
                   let provider = configManager.providers.first(where: { $0.id == providerId }) {
                    doLaunch(terminal: terminal, provider: provider, mode: .newTab)
                }
            }
            Button(L10n.t("new_window")) {
                if let terminal = pendingTerminal,
                   let providerId = anthropicModelProviderBinding.wrappedValue,
                   let provider = configManager.providers.first(where: { $0.id == providerId }) {
                    doLaunch(terminal: terminal, provider: provider, mode: .newWindow)
                }
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.format("terminal_running_message", pendingTerminal?.name ?? ""))
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
            // 终端选择
            HStack(spacing: 0) {
                Text(L10n.t("select_terminal"))
                    .font(.headline)
                    .frame(width: 100, alignment: .leading)

                Picker("", selection: $selectedTerminalId) {
                    ForEach(availableTerminals) { terminal in
                        Text(terminal.name).tag(terminal.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 360, alignment: .leading)

                Spacer()
            }

            // 工作目录选择
            HStack(spacing: 0) {
                Text(L10n.t("working_directory"))
                    .font(.headline)
                    .frame(width: 100, alignment: .leading)

                HStack(spacing: 4) {
                    Menu {
                        if recentDirectories.isEmpty {
                            Text(L10n.t("no_recent_dirs"))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(recentDirectories, id: \.self) { path in
                                Button {
                                    workingDirectory = path
                                } label: {
                                    Text(path)
                                        .truncationMode(.middle)
                                        .lineLimit(1)
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                recentDirectories = []
                                ClaudeCodeLauncher.saveRecentDirectories([])
                            } label: {
                                Label(L10n.t("clear_history"), systemImage: "trash")
                            }
                        }
                    } label: {
                        Text(workingDirectory.isEmpty ? L10n.t("working_directory_hint") : workingDirectory)
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .foregroundColor(workingDirectory.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .menuStyle(.borderedButton)
                    .menuIndicator(.visible)
                    .frame(width: 320, alignment: .leading)

                    Button {
                        showDirectoryPicker = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .frame(width: 36)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    // MARK: - Environment Variables Section

    private var envVarsSection: some View {
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

            // 配置模板
            HStack(spacing: 12) {
                Text(L10n.t("config_template"))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 280, alignment: .leading)

                Menu {
                    ForEach(templates) { tmpl in
                        Button {
                            applyTemplate(tmpl)
                        } label: {
                            HStack {
                                Text(tmpl.name)
                                if activeTemplateName == tmpl.name && !isTemplateDirty {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    if activeTemplateName != nil && isTemplateDirty {
                        Button {
                            updateCurrentTemplate()
                        } label: {
                            Label(L10n.t("update_template"), systemImage: "checkmark.circle")
                        }
                        Button {
                            newTemplateName = ""
                            showSaveTemplateSheet = true
                        } label: {
                            Label(L10n.t("save_as_new_template"), systemImage: "plus")
                        }
                    } else {
                        Button {
                            newTemplateName = ""
                            showSaveTemplateSheet = true
                        } label: {
                            Label(L10n.t("save_as_template"), systemImage: "plus")
                        }
                    }
                    Divider()
                    Button {
                        restoreDefaults()
                    } label: {
                        Label(L10n.t("restore_defaults"), systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Text(templateDisplayText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.borderedButton)
                .menuIndicator(.visible)
                .frame(width: 140, alignment: .leading)

                // 右侧操作按钮
                if activeTemplateName != nil && !isTemplateDirty {
                    Button {
                        renameText = activeTemplateName ?? ""
                        showRenameTemplateSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        showDeleteTemplateConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if activeTemplateName != nil && isTemplateDirty {
                    Button {
                        updateCurrentTemplate()
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L10n.t("update_template"))
                }

                Spacer()
            }

            // ANTHROPIC_MODEL (必填)
            modelPickerRow(
                name: "ANTHROPIC_MODEL",
                providerId: anthropicModelProviderBinding,
                model: $savedAnthropicModel,
                isRequired: true,
                onModelChange: markTemplateDirty
            )

            // 其他模型配置
            modelPickerRow(
                name: "ANTHROPIC_DEFAULT_OPUS_MODEL",
                providerId: opusModelProviderBinding,
                model: $savedOpusModel,
                onModelChange: markTemplateDirty
            )

            modelPickerRow(
                name: "ANTHROPIC_DEFAULT_SONNET_MODEL",
                providerId: sonnetModelProviderBinding,
                model: $savedSonnetModel,
                onModelChange: markTemplateDirty
            )

            modelPickerRow(
                name: "ANTHROPIC_DEFAULT_HAIKU_MODEL",
                providerId: haikuModelProviderBinding,
                model: $savedHaikuModel,
                onModelChange: markTemplateDirty
            )

            modelPickerRow(
                name: "CLAUDE_CODE_SUBAGENT_MODEL",
                providerId: subagentModelProviderBinding,
                model: $savedSubagentModel,
                onModelChange: markTemplateDirty
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
                .frame(width: 200, alignment: .leading)
                .onChange(of: effortLevel) { _, _ in
                    guard !isApplyingTemplate else { return }
                    saveSettings()
                    markTemplateDirty()
                }

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
                    .onChange(of: disableAttributionHeader) { _, _ in
                        guard !isApplyingTemplate else { return }
                        saveSettings()
                        markTemplateDirty()
                    }

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
                    .onChange(of: rectifierEnabled) { _, _ in
                        guard !isApplyingTemplate else { return }
                        saveSettings()
                        markTemplateDirty()
                    }

                Spacer()
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
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

    private func modelPickerRow(name: String, providerId: Binding<UUID?>, model: Binding<String>, isRequired: Bool = false, onModelChange: (() -> Void)? = nil) -> some View {
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

            Picker("", selection: providerId) {
                Text(L10n.t("please_select")).tag(UUID?.none)
                ForEach(configManager.providers) { provider in
                    Text(provider.name).tag(provider.id as UUID?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140, alignment: .leading)
            .offset(x: -8)
            .onChange(of: providerId.wrappedValue) { oldValue, newValue in
                guard !isApplyingTemplate else { return }
                if oldValue != newValue {
                    model.wrappedValue = ""
                    onModelChange?()
                }
            }

            let selectedProvider = providerId.wrappedValue.flatMap { id in
                configManager.providers.first(where: { $0.id == id })
            }
            Picker("", selection: model) {
                Text(isRequired ? L10n.t("please_select") : L10n.t("none")).tag("")
                if let provider = selectedProvider {
                    ForEach(enabledMappings(provider: provider), id: \.id) { mapping in
                        Text(mapping.incomingModel).tag(mapping.incomingModel)
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200, alignment: .leading)
            .offset(x: -8)
            .labelsHidden()
            .disabled(selectedProvider == nil)

            Spacer()
        }
        .onChange(of: model.wrappedValue) { _, _ in
            guard !isApplyingTemplate else { return }
            onModelChange?()
        }
    }

    private func enabledMappings(provider: ProviderConfig) -> [ModelMapping] {
        configManager.mappings.filter { $0.providerConfigId == provider.id && $0.isEnabled }
    }

    private var templateDisplayText: String {
        if let name = activeTemplateName {
            return isTemplateDirty ? "\(name) *" : name
        }
        return L10n.t("custom_config")
    }

    private func markTemplateDirty() {
        if activeTemplateName != nil {
            isTemplateDirty = true
        }
    }

    private func updateCurrentTemplate() {
        guard let name = activeTemplateName,
              let index = templates.firstIndex(where: { $0.name == name }) else { return }
        templates[index] = LaunchTemplate(
            id: templates[index].id,
            name: name,
            anthropicModel: savedAnthropicModel,
            anthropicModelProviderId: savedAnthropicModelProviderId,
            opusModel: savedOpusModel,
            opusModelProviderId: savedOpusModelProviderId,
            sonnetModel: savedSonnetModel,
            sonnetModelProviderId: savedSonnetModelProviderId,
            haikuModel: savedHaikuModel,
            haikuModelProviderId: savedHaikuModelProviderId,
            subagentModel: savedSubagentModel,
            subagentModelProviderId: savedSubagentModelProviderId,
            effortLevel: effortLevel,
            disableAttributionHeader: disableAttributionHeader,
            rectifierEnabled: rectifierEnabled
        )
        ClaudeCodeLauncher.saveTemplates(templates)
        isTemplateDirty = false
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
        // 标记正在加载，避免 onChange 回调干扰
        isApplyingTemplate = true

        if availableTerminals.contains(where: { $0.id == savedTerminalId }) {
            selectedTerminalId = savedTerminalId
        } else if let first = availableTerminals.first {
            selectedTerminalId = first.id
        }

        workingDirectory = savedWorkingDirectory

        effortLevel = savedEffortLevel
        disableAttributionHeader = savedDisableAttributionHeader
        rectifierEnabled = savedRectifierEnabled
        recentDirectories = ClaudeCodeLauncher.loadRecentDirectories()
        templates = ClaudeCodeLauncher.loadTemplates()
        if let savedName = UserDefaults.standard.string(forKey: "launcher.activeTemplateName"),
           let tmpl = templates.first(where: { $0.name == savedName }) {
            activeTemplateName = savedName
            // 检查当前值是否与模板匹配，设置 dirty 状态
            isTemplateDirty = !templateMatchesCurrent(tmpl)
        } else {
            activeTemplateName = nil
            isTemplateDirty = false
        }

        // 延迟重置标志，确保 SwiftUI 视图更新完成后再重置
        DispatchQueue.main.async {
            isApplyingTemplate = false
        }
    }

    private func templateMatchesCurrent(_ tmpl: LaunchTemplate) -> Bool {
        savedAnthropicModel == tmpl.anthropicModel &&
        savedAnthropicModelProviderId == tmpl.anthropicModelProviderId &&
        savedOpusModel == tmpl.opusModel &&
        savedOpusModelProviderId == tmpl.opusModelProviderId &&
        savedSonnetModel == tmpl.sonnetModel &&
        savedSonnetModelProviderId == tmpl.sonnetModelProviderId &&
        savedHaikuModel == tmpl.haikuModel &&
        savedHaikuModelProviderId == tmpl.haikuModelProviderId &&
        savedSubagentModel == tmpl.subagentModel &&
        savedSubagentModelProviderId == tmpl.subagentModelProviderId &&
        effortLevel == (tmpl.effortLevel ?? "") &&
        disableAttributionHeader == (tmpl.disableAttributionHeader ?? false) &&
        rectifierEnabled == (tmpl.rectifierEnabled ?? true)
    }

    private func saveSettings() {
        savedTerminalId = selectedTerminalId
        savedWorkingDirectory = workingDirectory
        savedEffortLevel = effortLevel
        savedDisableAttributionHeader = disableAttributionHeader
        savedRectifierEnabled = rectifierEnabled
    }

    private func applyTemplate(_ tmpl: LaunchTemplate) {
        // 标记正在应用模板，避免 onChange 回调干扰
        isApplyingTemplate = true
        activeTemplateName = tmpl.name
        isTemplateDirty = false
        UserDefaults.standard.set(tmpl.name, forKey: "launcher.activeTemplateName")
        savedAnthropicModel = tmpl.anthropicModel
        savedAnthropicModelProviderId = tmpl.anthropicModelProviderId
        savedOpusModel = tmpl.opusModel
        savedOpusModelProviderId = tmpl.opusModelProviderId
        savedSonnetModel = tmpl.sonnetModel
        savedSonnetModelProviderId = tmpl.sonnetModelProviderId
        savedHaikuModel = tmpl.haikuModel
        savedHaikuModelProviderId = tmpl.haikuModelProviderId
        savedSubagentModel = tmpl.subagentModel
        savedSubagentModelProviderId = tmpl.subagentModelProviderId
        if let effort = tmpl.effortLevel {
            effortLevel = effort
            savedEffortLevel = effort
        }
        if let attr = tmpl.disableAttributionHeader {
            disableAttributionHeader = attr
            savedDisableAttributionHeader = attr
        }
        if let rect = tmpl.rectifierEnabled {
            rectifierEnabled = rect
            savedRectifierEnabled = rect
        }
        // 延迟重置标志，确保 SwiftUI 视图更新完成后再重置
        DispatchQueue.main.async {
            isApplyingTemplate = false
        }
    }

    private func saveCurrentAsTemplate(name: String) {
        let newTemplate = LaunchTemplate(
            name: name,
            anthropicModel: savedAnthropicModel,
            anthropicModelProviderId: savedAnthropicModelProviderId,
            opusModel: savedOpusModel,
            opusModelProviderId: savedOpusModelProviderId,
            sonnetModel: savedSonnetModel,
            sonnetModelProviderId: savedSonnetModelProviderId,
            haikuModel: savedHaikuModel,
            haikuModelProviderId: savedHaikuModelProviderId,
            subagentModel: savedSubagentModel,
            subagentModelProviderId: savedSubagentModelProviderId,
            effortLevel: effortLevel,
            disableAttributionHeader: disableAttributionHeader,
            rectifierEnabled: rectifierEnabled
        )
        templates.append(newTemplate)
        ClaudeCodeLauncher.saveTemplates(templates)
        // 保存后激活新模板
        activeTemplateName = name
        isTemplateDirty = false
        UserDefaults.standard.set(name, forKey: "launcher.activeTemplateName")
    }

    private func deleteTemplate(_ tmpl: LaunchTemplate) {
        templates.removeAll { $0.id == tmpl.id }
        ClaudeCodeLauncher.saveTemplates(templates)
        if activeTemplateName == tmpl.name {
            activeTemplateName = nil
            isTemplateDirty = false
            UserDefaults.standard.removeObject(forKey: "launcher.activeTemplateName")
        }
    }

    private func renameTemplate(_ tmpl: LaunchTemplate, to newName: String) {
        if let index = templates.firstIndex(where: { $0.id == tmpl.id }) {
            templates[index].name = newName
            ClaudeCodeLauncher.saveTemplates(templates)
            if activeTemplateName == tmpl.name {
                activeTemplateName = newName
                UserDefaults.standard.set(newName, forKey: "launcher.activeTemplateName")
            }
        }
    }

    private func restoreDefaults() {
        activeTemplateName = nil
        isTemplateDirty = false
        UserDefaults.standard.removeObject(forKey: "launcher.activeTemplateName")
        templates = ClaudeCodeLauncher.defaultTemplates()
        ClaudeCodeLauncher.saveTemplates(templates)
    }

    private func launchClaudeCode() {
        guard let terminal = selectedTerminal else {
            errorMessage = L10n.t("no_terminal_selected")
            return
        }
        guard let providerId = anthropicModelProviderBinding.wrappedValue,
              let defaultProvider = configManager.providers.first(where: { $0.id == providerId }) else {
            errorMessage = L10n.t("no_provider_selected")
            return
        }

        isLaunching = true
        errorMessage = nil

        // 检测终端是否已运行
        if ClaudeCodeLauncher.isTerminalRunning(terminal) {
            // 检测终端是否有可见窗口
            if ClaudeCodeLauncher.hasVisibleWindow(terminal) {
                // 有可见窗口 - 显示选择对话框（新建标签页/新建窗口/取消）
                isLaunching = false
                pendingTerminal = terminal
                showTerminalRunningAlert = true
                return
            } else {
                // 无可见窗口 - 直接新建窗口，无需选择
                doLaunch(terminal: terminal, provider: defaultProvider, mode: .newWindow)
                return
            }
        }

        // 终端未运行 - 直接新建窗口启动
        doLaunch(terminal: terminal, provider: defaultProvider, mode: .newWindow)
    }

    private func doLaunch(terminal: TerminalApp, provider: ProviderConfig, mode: TerminalLaunchMode) {
        isLaunching = true
        errorMessage = nil

        var customEnvVars: [String: String] = [
            "ANTHROPIC_BASE_URL": localBaseURL,
            "ANTHROPIC_AUTH_TOKEN": "1234",
            "ANTHROPIC_MODEL": ClaudeCodeLauncher.with1MContextSuffix(savedAnthropicModel)
        ]

        if !savedOpusModel.isEmpty { customEnvVars["ANTHROPIC_DEFAULT_OPUS_MODEL"] = ClaudeCodeLauncher.with1MContextSuffix(savedOpusModel) }
        if !savedSonnetModel.isEmpty { customEnvVars["ANTHROPIC_DEFAULT_SONNET_MODEL"] = ClaudeCodeLauncher.with1MContextSuffix(savedSonnetModel) }
        if !savedHaikuModel.isEmpty { customEnvVars["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = ClaudeCodeLauncher.with1MContextSuffix(savedHaikuModel) }
        if !savedSubagentModel.isEmpty { customEnvVars["CLAUDE_CODE_SUBAGENT_MODEL"] = ClaudeCodeLauncher.with1MContextSuffix(savedSubagentModel) }
        if !effortLevel.isEmpty { customEnvVars["CLAUDE_CODE_EFFORT_LEVEL"] = effortLevel }

        let workDir = workingDirectory.isEmpty ? nil : URL(fileURLWithPath: workingDirectory)

        let launcher = ClaudeCodeLauncher()
        let configuration = LaunchConfiguration(
            provider: provider,
            selectedMapping: nil,
            customEnvVars: customEnvVars,
            workingDirectory: workDir,
            disableAttributionHeader: disableAttributionHeader,
            launchMode: mode
        )

        do {
            try launcher.launchInTerminal(terminal: terminal, configuration: configuration)
            // 记录工作目录到历史
            if !workingDirectory.isEmpty {
                ClaudeCodeLauncher.addRecentDirectory(workingDirectory)
            }
            isLaunching = false
            dismiss()
        } catch {
            isLaunching = false
            errorMessage = error.localizedDescription
        }
    }
}
