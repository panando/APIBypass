import SwiftUI
import AppKit
import CodexRouterCore

struct CodexAdaptorView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var codexAdaptor: CodexAdaptorService

    @State private var config = CodexAdaptorConfig()
    @State private var portText = "15721"

    // Log filter
    @State private var logFilter = ""
    @State private var logStore = CodexLogStore.shared

    // Save state
    @State private var showSaveConfirmation = false
    @State private var hasUnsavedChanges = false

    // Auto-detect state
    @State private var isInferring = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Service Section
                serviceSection

                Divider()

                // Communication Protocol Section
                communicationSection

                Divider()

                // Reasoning Configuration Section
                reasoningSection

                Divider()

                // Custom Models Section
                customModelsSection

                Divider()

                // Codex Enhancements (CDP) Section
                cdpSection

                Divider()

                // Logs Section
                logsSection
            }
            .padding()
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 600)
        .navigationTitle(L10n.t("codex_adaptor_title"))
        .onAppear {
            loadConfig()
        }
    }

    // MARK: - Service Section

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("codex_service"))
                .font(.headline)

            HStack {
                if codexAdaptor.isRunning {
                    Button(action: {
                        Task { await codexAdaptor.stop() }
                    }) {
                        Label(L10n.t("codex_stop"), systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button(action: {
                        Task { try? await codexAdaptor.start() }
                    }) {
                        Label(L10n.t("codex_start"), systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }

                Spacer()

                Text(L10n.t("codex_port"))
                TextField("15721", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onChange(of: portText) { _, newValue in
                        if let port = Int(newValue), port > 0, port <= 65535 {
                            config.port = port
                            markUnsaved()
                        }
                    }
            }

            HStack {
                Circle()
                    .fill(codexAdaptor.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(codexAdaptor.isRunning ? L10n.t("codex_status_running") : L10n.t("codex_status_stopped"))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Communication Protocol Section

    private var communicationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("codex_communication"))
                .font(.headline)

            Picker(L10n.t("codex_wire_api"), selection: $config.wireAPI) {
                ForEach(CodexAdaptorConfig.WireAPI.allCases, id: \.self) { api in
                    Text(api.displayName).tag(api)
                }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: config.wireAPI) { _, _ in markUnsaved() }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Reasoning Configuration Section

    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("codex_reasoning"))
                .font(.headline)

            Toggle(L10n.t("codex_reasoning_override"), isOn: $config.reasoningOverrideEnabled)
                .onChange(of: config.reasoningOverrideEnabled) { _, _ in markUnsaved() }

            if config.reasoningOverrideEnabled {
                Button(action: { inferReasoningConfig() }) {
                    Label(L10n.t("codex_auto_detect"), systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(isInferring)

                if let rc = config.reasoningConfig {
                    Group {
                        Picker(L10n.t("codex_thinking_param"), selection: Binding(
                            get: { rc.thinkingParam ?? "" },
                            set: { newValue in
                                config.reasoningConfig = ReasoningConfig(
                                    supportsThinking: rc.supportsThinking,
                                    supportsEffort: rc.supportsEffort,
                                    thinkingParam: newValue.isEmpty ? nil : newValue,
                                    effortParam: rc.effortParam,
                                    effortValueMode: rc.effortValueMode,
                                    outputFormat: rc.outputFormat
                                )
                                markUnsaved()
                            }
                        )) {
                            Text("None").tag("")
                            Text("enable_thinking").tag("enable_thinking")
                            Text("thinking").tag("thinking")
                            Text("reasoning_split").tag("reasoning_split")
                        }

                        Picker(L10n.t("codex_effort_param"), selection: Binding(
                            get: { rc.effortParam ?? "" },
                            set: { newValue in
                                config.reasoningConfig = ReasoningConfig(
                                    supportsThinking: rc.supportsThinking,
                                    supportsEffort: rc.supportsEffort,
                                    thinkingParam: rc.thinkingParam,
                                    effortParam: newValue.isEmpty ? nil : newValue,
                                    effortValueMode: rc.effortValueMode,
                                    outputFormat: rc.outputFormat
                                )
                                markUnsaved()
                            }
                        )) {
                            Text("None").tag("")
                            Text("reasoning_effort").tag("reasoning_effort")
                            Text("reasoning.effort").tag("reasoning.effort")
                        }

                        Picker(L10n.t("codex_effort_value"), selection: Binding(
                            get: { rc.effortValueMode ?? "" },
                            set: { newValue in
                                config.reasoningConfig = ReasoningConfig(
                                    supportsThinking: rc.supportsThinking,
                                    supportsEffort: rc.supportsEffort,
                                    thinkingParam: rc.thinkingParam,
                                    effortParam: rc.effortParam,
                                    effortValueMode: newValue.isEmpty ? nil : newValue,
                                    outputFormat: rc.outputFormat
                                )
                                markUnsaved()
                            }
                        )) {
                            Text("None").tag("")
                            Text("deepseek").tag("deepseek")
                            Text("openrouter").tag("openrouter")
                            Text("low_high").tag("low_high")
                        }

                        Picker(L10n.t("codex_output_format"), selection: Binding(
                            get: { rc.outputFormat ?? "" },
                            set: { newValue in
                                config.reasoningConfig = ReasoningConfig(
                                    supportsThinking: rc.supportsThinking,
                                    supportsEffort: rc.supportsEffort,
                                    thinkingParam: rc.thinkingParam,
                                    effortParam: rc.effortParam,
                                    effortValueMode: rc.effortValueMode,
                                    outputFormat: newValue.isEmpty ? nil : newValue
                                )
                                markUnsaved()
                            }
                        )) {
                            Text("None").tag("")
                            Text("reasoning_content").tag("reasoning_content")
                            Text("reasoning_details").tag("reasoning_details")
                            Text("reasoning").tag("reasoning")
                            Text("auto").tag("auto")
                        }
                    }
                } else {
                    Text(L10n.t("codex_no_reasoning_config"))
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Custom Models Section

    private var customModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("codex_custom_models"))
                    .font(.headline)
                Spacer()
                Button(action: { addCustomModel() }) {
                    Label(L10n.t("codex_add_model"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if config.customModels.isEmpty {
                Text(L10n.t("codex_no_custom_models"))
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach($config.customModels) { $entry in
                    HStack(spacing: 8) {
                        TextField(L10n.t("codex_alias"), text: $entry.alias)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 120)
                            .onChange(of: entry.alias) { _, _ in markUnsaved() }

                        Picker("", selection: $entry.modelMappingId) {
                            ForEach(CodexConfigBridge.availableMappings(from: configManager)) { mapping in
                                Text(mapping.incomingModel).tag(mapping.id)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 150)
                        .onChange(of: entry.modelMappingId) { _, _ in markUnsaved() }

                        TextField(L10n.t("codex_context_window"), value: $entry.contextWindow, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: entry.contextWindow) { _, _ in markUnsaved() }

                        Button(action: { removeCustomModel(entry.id) }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Codex Enhancements (CDP) Section

    private var cdpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("codex_cdp_title"))
                .font(.headline)

            Toggle(L10n.t("codex_plugin_entry_unlock"), isOn: $config.cdpSettings.codexAppPluginEntryUnlock)
                .onChange(of: config.cdpSettings.codexAppPluginEntryUnlock) { _, _ in markUnsaved() }

            Toggle(L10n.t("codex_marketplace_unlock"), isOn: $config.cdpSettings.codexAppPluginMarketplaceUnlock)
                .onChange(of: config.cdpSettings.codexAppPluginMarketplaceUnlock) { _, _ in markUnsaved() }

            Toggle(L10n.t("codex_force_plugin_install"), isOn: $config.cdpSettings.codexAppForcePluginInstall)
                .onChange(of: config.cdpSettings.codexAppForcePluginInstall) { _, _ in markUnsaved() }

            HStack {
                Text(L10n.t("codex_debug_port"))
                TextField("9222", value: $config.cdpDebugPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onChange(of: config.cdpDebugPort) { _, _ in markUnsaved() }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("codex_logs"))
                    .font(.headline)
                Spacer()

                TextField(L10n.t("codex_log_filter"), text: $logFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                Button(action: { copyLogs() }) {
                    Label(L10n.t("codex_copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button(action: { exportLogs() }) {
                    Label(L10n.t("codex_export"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Button(action: { logStore.clear() }) {
                    Label(L10n.t("codex_clear"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredLogs) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.level.rawValue)
                                    .font(.caption)
                                    .foregroundColor(entry.level.color)
                                    .frame(width: 50, alignment: .leading)

                                Text(entry.timestamp)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Text(entry.message)
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 300)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
                .onChange(of: logStore.entries.count) { _, _ in
                    if let last = filteredLogs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private var filteredLogs: [LogEntry] {
        if logFilter.isEmpty {
            return logStore.entries
        }
        return logStore.entries.filter {
            $0.message.localizedCaseInsensitiveContains(logFilter)
                || $0.level.rawValue.localizedCaseInsensitiveContains(logFilter)
        }
    }

    private func loadConfig() {
        Task {
            config = await CodexAdaptorConfigStore.shared.load()
            portText = String(config.port)
        }
    }

    private func markUnsaved() {
        hasUnsavedChanges = true
    }

    private func inferReasoningConfig() {
        isInferring = true
        guard let provider = configManager.providers.first else {
            isInferring = false
            return
        }
        let mapping = configManager.mappings.first
        let modelName = mapping?.incomingModel ?? ""
        let inferred = ReasoningConfig.infer(
            name: provider.name,
            baseURL: provider.baseURL.absoluteString,
            model: modelName
        )
        config.reasoningConfig = inferred
        isInferring = false
        markUnsaved()
    }

    private func addCustomModel() {
        guard let firstMapping = CodexConfigBridge.availableMappings(from: configManager).first else { return }
        let entry = CustomModelEntry(
            alias: firstMapping.incomingModel,
            modelMappingId: firstMapping.id
        )
        config.customModels.append(entry)
        markUnsaved()
    }

    private func removeCustomModel(_ id: UUID) {
        config.customModels.removeAll { $0.id == id }
        markUnsaved()
    }

    private func copyLogs() {
        let text = filteredLogs.map { "[\($0.level.rawValue)] \($0.timestamp) \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "codex_adaptor.log"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let text = filteredLogs.map { "[\($0.level.rawValue)] \($0.timestamp) \($0.message)" }.joined(separator: "\n")
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
