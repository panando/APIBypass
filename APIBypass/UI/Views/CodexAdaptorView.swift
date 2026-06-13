import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CodexRouterCore

// MARK: - Config Tab

private enum ConfigTab: String, CaseIterable, Identifiable {
    case server
    case logs
    case help
    case about

    var id: String { rawValue }
}

// MARK: - Main View

struct CodexAdaptorView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var codexAdaptor: CodexAdaptorService

    @State private var selectedTab: ConfigTab? = .server

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            List(selection: $selectedTab) {
                Section {
                    sidebarItem(tab: .server, icon: "network") {
                        Circle()
                            .fill(codexAdaptor.isRunning ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                    }
                }
                Section {
                    sidebarItem(tab: .help, icon: "questionmark.circle")
                    sidebarItem(tab: .logs, icon: "doc.text.magnifyingglass")
                    sidebarItem(tab: .about, icon: "info.circle")
                }
            }
            .listStyle(.sidebar)
            .frame(width: 180)

            Divider()

            // Detail
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 780, minHeight: 560)
    }

    private func sidebarItem(tab: ConfigTab, icon: String) -> some View {
        Label(L10n.t(tab.titleKey), systemImage: icon)
            .tag(tab)
    }

    private func sidebarItem<V: View>(tab: ConfigTab, icon: String, @ViewBuilder trailing: @escaping () -> V) -> some View {
        Label {
            HStack(spacing: 6) {
                Text(L10n.t(tab.titleKey))
                Spacer()
                trailing()
            }
        } icon: {
            Image(systemName: icon)
        }
        .tag(tab)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .server:
            CodexServerTab(configManager: configManager, codexAdaptor: codexAdaptor)
        case .logs:
            CodexLogViewerTab()
        case .help:
            CodexHelpTab()
        case .about:
            CodexAboutTab()
        case nil:
            VStack {
                Image(systemName: "gearshape")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text(L10n.t("codex_select_section"))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - ConfigTab Title Keys

private extension ConfigTab {
    var titleKey: String {
        switch self {
        case .server: return "codex_service"
        case .logs: return "codex_logs"
        case .help: return "help"
        case .about: return "about"
        }
    }
}

// MARK: - Server Tab

private struct CodexServerTab: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var codexAdaptor: CodexAdaptorService

    @State private var config = CodexAdaptorConfig()
    @State private var portText = "15721"
    @State private var proxyURL = "http://127.0.0.1:15721/v1"
    @State private var showReasoningConfig = false
    @State private var supportsThinking = false
    @State private var supportsEffort = false
    @State private var thinkingParam = "thinking"
    @State private var effortParam = "reasoning_effort"
    @State private var effortValueMode = "standard"
    @State private var reasoningOutputFormat = "reasoning_content"
    @State private var showAddModel = false
    @State private var newModelAlias = ""
    @State private var newModelMappingId: UUID?
    @State private var newModelContextWindow = "128000"
    @State private var modelIndexToDelete: Int?

    var body: some View {
        Form {
            // Runtime Status
            Section {
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(codexAdaptor.isRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(codexAdaptor.isRunning ? L10n.t("codex_status_running") : L10n.t("codex_status_stopped"))
                            .fontWeight(.medium)
                        if codexAdaptor.isRunning {
                            Text("(\(L10n.t("codex_port")) \(String(codexAdaptor.port)))")
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button(action: {
                        Task {
                            if codexAdaptor.isRunning {
                                await codexAdaptor.stop()
                            } else {
                                try? await codexAdaptor.start()
                            }
                        }
                    }) {
                        Label(
                            codexAdaptor.isRunning ? L10n.t("codex_stop") : L10n.t("codex_start"),
                            systemImage: codexAdaptor.isRunning ? "stop.circle" : "play.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } header: {
                Label(L10n.t("codex_runtime_status"), systemImage: "power")
            }

            // Communication Protocol
            Section {
                Picker(L10n.t("codex_wire_api"), selection: $config.wireAPI) {
                    ForEach(CodexAdaptorConfig.WireAPI.allCases, id: \.self) { api in
                        Text(api.displayName).tag(api)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: config.wireAPI) { _, _ in saveConfig() }
            } header: {
                Label(L10n.t("codex_wire_api"), systemImage: "arrow.triangle.swap")
            }

            // Proxy Server
            Section {
                HStack(spacing: 8) {
                    Text(L10n.t("codex_proxy_port"))
                        .frame(width: 96, alignment: .leading)
                    TextField("", text: $portText)
                        .textFieldStyle(.roundedBorder)
                    Text(L10n.t("codex_requires_restart"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 112, alignment: .leading)
                }
                HStack(spacing: 8) {
                    Text(L10n.t("codex_proxy_url"))
                        .frame(width: 96, alignment: .leading)
                    TextField("", text: .constant(proxyURL))
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    Text(L10n.t("codex_auto_configured"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 112, alignment: .leading)
                }
            } header: {
                Text(L10n.t("codex_proxy_server"))
            }

            // Reasoning Configuration (card-style section)
            Section {
                reasoningSection
            }

            // Custom Models (card-style section)
            Section {
                customModelsSection
            }

            // Codex Enhancements
            Section {
                Toggle(isOn: $config.cdpSettings.codexAppPluginEntryUnlock) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("codex_plugin_entry_unlock")).fontWeight(.medium)
                        Text(L10n.t("codex_plugin_entry_unlock_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: config.cdpSettings.codexAppPluginEntryUnlock) { _, _ in
                    saveConfig()
                    Task { await codexAdaptor.pushInjectionSettings() }
                }

                Toggle(isOn: $config.cdpSettings.codexAppPluginMarketplaceUnlock) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("codex_marketplace_unlock")).fontWeight(.medium)
                        Text(L10n.t("codex_marketplace_unlock_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: config.cdpSettings.codexAppPluginMarketplaceUnlock) { _, _ in
                    saveConfig()
                    Task { await codexAdaptor.pushInjectionSettings() }
                }

                Toggle(isOn: $config.cdpSettings.codexAppForcePluginInstall) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("codex_force_plugin_install")).fontWeight(.medium)
                        Text(L10n.t("codex_force_plugin_install_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: config.cdpSettings.codexAppForcePluginInstall) { _, _ in
                    saveConfig()
                    Task { await codexAdaptor.pushInjectionSettings() }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(L10n.t("codex_debug_port"))
                            .frame(width: 96, alignment: .leading)
                        TextField("", value: $config.cdpDebugPort, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                    }
                    Text(L10n.t("codex_debug_port_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .onChange(of: config.cdpDebugPort) { _, _ in saveConfig() }
            } header: {
                Label(L10n.t("codex_enhancements"), systemImage: "wand.and.stars")
            }
        }
        .formStyle(.grouped)
        .onAppear { loadConfig() }
        .onChange(of: portText) { _, newValue in
            if let portValue = Int(newValue), portValue > 0, portValue <= 65535 {
                config.port = portValue
                proxyURL = "http://127.0.0.1:\(portValue)/v1"
                saveConfig()
            }
        }
    }

    // MARK: - Reasoning Section

    @ViewBuilder
    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Label(L10n.t("codex_reasoning"), systemImage: "brain.head.profile")
                .font(.headline)
                .padding(.bottom, 10)

            // Toggle row
            HStack {
                Toggle("", isOn: $config.reasoningOverrideEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                Text(L10n.t("codex_override_reasoning"))
                Spacer()
                Button(L10n.t("codex_auto_detect")) {
                    inferReasoningConfig()
                }
                .controlSize(.small)
                .disabled(configManager.providers.isEmpty)
            }

            if !config.reasoningOverrideEnabled {
                // Footer when disabled
                Text(L10n.t("codex_reasoning_auto_footer"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }

            if config.reasoningOverrideEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    // Thinking
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Toggle("", isOn: $supportsThinking)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .controlSize(.small)
                            Text(L10n.t("codex_enable_thinking"))
                        }
                        Text(L10n.t("codex_thinking_desc"))
                            .font(.caption).foregroundColor(.secondary)

                        if supportsThinking {
                            Picker(L10n.t("codex_thinking_param"), selection: $thinkingParam) {
                                Text("thinking -- DeepSeek / Kimi / GLM").tag("thinking")
                                Text("enable_thinking -- SiliconFlow / Qwen").tag("enable_thinking")
                                Text("reasoning_split -- MiniMax").tag("reasoning_split")
                                Text("none -- skip").tag("none")
                            }
                        }
                    }

                    Divider()

                    // Effort
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Toggle("", isOn: $supportsEffort)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .controlSize(.small)
                            Text(L10n.t("codex_enable_effort"))
                        }
                        Text(L10n.t("codex_effort_desc"))
                            .font(.caption).foregroundColor(.secondary)

                        if supportsEffort {
                            Picker(L10n.t("codex_effort_param"), selection: $effortParam) {
                                Text("reasoning_effort -- top-level").tag("reasoning_effort")
                                Text("reasoning.effort -- nested").tag("reasoning.effort")
                            }

                            Picker(L10n.t("codex_effort_value"), selection: $effortValueMode) {
                                Text("Standard -- passthrough").tag("standard")
                                Text("DeepSeek -- max/xhigh to max").tag("deepseek")
                                Text("OpenRouter -- max to xhigh").tag("openrouter")
                                Text("Low/High -- binary").tag("low_high")
                            }
                        }
                    }

                    Divider()

                    // Output Format
                    VStack(alignment: .leading, spacing: 4) {
                        Picker(L10n.t("codex_output_format"), selection: $reasoningOutputFormat) {
                            Text("reasoning_content -- single string").tag("reasoning_content")
                            Text("reasoning_details -- array of parts").tag("reasoning_details")
                            Text("reasoning -- generic field").tag("reasoning")
                            Text("auto -- no transformation").tag("auto")
                        }
                        Text(L10n.t("codex_output_format_desc"))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .onChange(of: supportsThinking) { _, _ in updateReasoningConfig() }
        .onChange(of: supportsEffort) { _, _ in updateReasoningConfig() }
        .onChange(of: thinkingParam) { _, _ in updateReasoningConfig() }
        .onChange(of: effortParam) { _, _ in updateReasoningConfig() }
        .onChange(of: effortValueMode) { _, _ in updateReasoningConfig() }
        .onChange(of: reasoningOutputFormat) { _, _ in updateReasoningConfig() }
        .onChange(of: config.reasoningOverrideEnabled) { _, _ in updateReasoningConfig() }
    }

    // MARK: - Custom Models Section

    @ViewBuilder
    private var customModelsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Label(L10n.t("codex_custom_models"), systemImage: "cube.box")
                .font(.headline)
                .padding(.bottom, 10)

            // Footer
            Text(L10n.t("codex_model_footer"))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            // Column headers
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 12) {
                    Text(L10n.t("codex_model_alias"))
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.t("codex_model_slug"))
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.t("codex_context_window"))
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer().frame(width: 60)
                }
                HStack(spacing: 12) {
                    Text(L10n.t("codex_model_alias_desc"))
                        .font(.caption2).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.t("codex_model_slug_desc"))
                        .font(.caption2).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.t("codex_context_window_eg"))
                        .font(.caption2).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer().frame(width: 60)
                }
            }
            .padding(.bottom, 4)

            // Existing model rows
            ForEach(Array(config.customModels.enumerated()), id: \.element.id) { index, _ in
                HStack(spacing: 12) {
                    TextField(L10n.t("codex_model_alias"), text: $config.customModels[index].alias)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)

                    Picker("", selection: $config.customModels[index].modelMappingId) {
                        ForEach(CodexConfigBridge.availableMappings(from: configManager)) { mapping in
                            Text(mapping.incomingModel).tag(mapping.id)
                        }
                    }
                    .labelsHidden()
                        .frame(maxWidth: .infinity)

                    TextField(L10n.t("codex_context_window"), value: $config.customModels[index].contextWindow, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)

                    Button {
                        modelIndexToDelete = index
                    } label: {
                        Image(systemName: "trash")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 60)
                }
            }

            // Inline add form
            if showAddModel {
                HStack(spacing: 12) {
                    TextField(L10n.t("codex_model_alias"), text: $newModelAlias)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)

                    Picker("", selection: $newModelMappingId) {
                        Text(L10n.t("please_select")).tag(nil as UUID?)
                        ForEach(CodexConfigBridge.availableMappings(from: configManager)) { mapping in
                            Text(mapping.incomingModel).tag(mapping.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    TextField(L10n.t("codex_context_window"), text: $newModelContextWindow)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 6) {
                        Button {
                            resetModelForm()
                            showAddModel = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            guard let mappingId = newModelMappingId else { return }
                            let entry = CustomModelEntry(
                                alias: newModelAlias.isEmpty ? (CodexConfigBridge.availableMappings(from: configManager).first { $0.id == mappingId }?.incomingModel ?? "") : newModelAlias,
                                modelMappingId: mappingId,
                                contextWindow: UInt64(newModelContextWindow) ?? 128000
                            )
                            config.customModels.append(entry)
                            resetModelForm()
                            showAddModel = false
                            saveConfig()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(newModelMappingId == nil)
                    }
                    .frame(width: 60)
                }
            }

            // Add Model button
            if !showAddModel {
                Button {
                    resetModelForm()
                    showAddModel = true
                } label: {
                    Label(L10n.t("codex_add_model"), systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .confirmationDialog(
            L10n.t("confirm_delete"),
            isPresented: Binding(
                get: { modelIndexToDelete != nil },
                set: { if !$0 { modelIndexToDelete = nil } }
            )
        ) {
            Button(L10n.t("delete"), role: .destructive) {
                if let idx = modelIndexToDelete {
                    config.customModels.remove(at: idx)
                    modelIndexToDelete = nil
                    saveConfig()
                }
            }
            Button(L10n.t("cancel"), role: .cancel) { modelIndexToDelete = nil }
        } message: {
            Text(L10n.t("confirm_delete_generic"))
        }
    }

    // MARK: - Helpers

    private func loadConfig() {
        Task {
            config = await CodexAdaptorConfigStore.shared.load()
            portText = String(config.port)
            proxyURL = "http://127.0.0.1:\(config.port)/v1"

            // Populate reasoning state
            if let rc = config.reasoningConfig {
                supportsThinking = rc.supportsThinking ?? false
                supportsEffort = rc.supportsEffort ?? false
                thinkingParam = rc.thinkingParam ?? "thinking"
                effortParam = rc.effortParam ?? "reasoning_effort"
                effortValueMode = rc.effortValueMode ?? "standard"
                reasoningOutputFormat = rc.outputFormat ?? "reasoning_content"
            }
            showReasoningConfig = config.reasoningOverrideEnabled
        }
    }

    private func saveConfig() {
        Task {
            try? await codexAdaptor.updateConfig(config)
        }
    }

    private func updateReasoningConfig() {
        if config.reasoningOverrideEnabled {
            config.reasoningConfig = ReasoningConfig(
                supportsThinking: supportsThinking ? true : nil,
                supportsEffort: supportsEffort ? true : nil,
                thinkingParam: thinkingParam == "none" ? "none" : thinkingParam,
                effortParam: supportsEffort ? effortParam : "none",
                effortValueMode: supportsEffort ? effortValueMode : nil,
                outputFormat: reasoningOutputFormat
            )
        } else {
            config.reasoningConfig = nil
        }
        saveConfig()
    }

    private func inferReasoningConfig() {
        guard let provider = configManager.providers.first else { return }
        let mapping = configManager.mappings.first
        let modelName = mapping?.incomingModel ?? ""
        let inferred = ReasoningConfig.infer(
            name: provider.name,
            baseURL: provider.baseURL.absoluteString,
            model: modelName
        )
        if let rc = inferred {
            supportsThinking = rc.supportsThinking ?? false
            supportsEffort = rc.supportsEffort ?? false
            thinkingParam = rc.thinkingParam ?? "thinking"
            effortParam = rc.effortParam ?? "reasoning_effort"
            effortValueMode = rc.effortValueMode ?? "standard"
            reasoningOutputFormat = rc.outputFormat ?? "reasoning_content"
            config.reasoningOverrideEnabled = true
            updateReasoningConfig()
        }
    }

    private func resetModelForm() {
        newModelAlias = ""
        newModelMappingId = nil
        newModelContextWindow = "128000"
    }
}

// MARK: - Log Viewer Tab

private struct CodexLogViewerTab: View {
    @ObservedObject private var logStore = CodexLogStore.shared
    @State private var autoScroll = true
    @State private var filterText = ""
    @State private var copyConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                TextField(L10n.t("codex_filter"), text: $filterText)
                    .textFieldStyle(.roundedBorder)
                Toggle(L10n.t("codex_auto_scroll"), isOn: $autoScroll)

                Button(L10n.t("codex_copy_all")) { copyAll() }
                Button(L10n.t("codex_export_logs")) { exportLogs() }
                Button(L10n.t("codex_clear_logs")) { logStore.clear() }
            }
            .padding(8)

            Divider()

            // Log list
            ScrollViewReader { proxy in
                List(filteredEntries) { entry in
                    CodexLogEntryRow(entry: entry)
                        .id(entry.id)
                }
                .onChange(of: logStore.entries.count) { _, _ in
                    if autoScroll, let last = filteredEntries.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            // Footer
            HStack {
                if copyConfirmation {
                    Text(L10n.t("codex_copied"))
                        .font(.caption).foregroundColor(.green)
                        .transition(.opacity)
                }
                Text("\(filteredEntries.count) \(L10n.t("codex_entries"))")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEntries: [LogEntry] {
        if filterText.isEmpty { return logStore.entries }
        return logStore.entries.filter { $0.message.localizedCaseInsensitiveContains(filterText) }
    }

    private func formatEntries(_ entries: [LogEntry]) -> String {
        entries.map { "[\($0.timestamp)] [\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
    }

    private func copyAll() {
        let text = formatEntries(filteredEntries)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copyConfirmation = false }
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.title = L10n.t("codex_export_logs")
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "codexadaptor-logs-\(df.string(from: Date())).txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let text = formatEntries(logStore.entries)
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

// MARK: - Log Entry Row

private struct CodexLogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(entry.level.rawValue)
                .font(.system(.caption2, design: .monospaced)).fontWeight(.bold)
                .foregroundColor(entry.level.color)
                .frame(width: 45, alignment: .leading)
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Help Tab

private struct CodexHelpTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.t("help_codex_adaptor"), systemImage: "questionmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text(L10n.t("codex_help_subtitle"))
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.t("codex_how_it_works"), systemImage: "arrow.triangle.swap")
                        .font(.headline)
                    Text(L10n.t("codex_how_it_works_desc"))
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.t("codex_setup_guide"), systemImage: "list.number")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        step(1, L10n.t("codex_setup_step1"))
                        step(2, L10n.t("codex_setup_step2"))
                        step(3, L10n.t("codex_setup_step3"))
                        step(4, L10n.t("codex_setup_step4"))
                        step(5, L10n.t("codex_setup_step5"))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.t("codex_config_files"), systemImage: "doc.text")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        fileEntry(path: "~/.codex/config.toml", desc: L10n.t("codex_file_config_desc"))
                        fileEntry(path: "~/.codex/providers.json", desc: L10n.t("codex_file_providers_desc"))
                        fileEntry(path: "~/.codex/<provider-id>-model-catalog.json", desc: L10n.t("codex_file_catalog_desc"))
                        fileEntry(path: "~/.codex/config.toml.bak.codexadaptor", desc: L10n.t("codex_file_backup_desc"))
                    }
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(_ num: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(num).")
                .font(.body).fontWeight(.medium)
                .foregroundColor(.blue)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.body)
        }
    }

    private func fileEntry(path: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(path)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(.primary)
            Text(desc)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - About Tab

private struct CodexAboutTab: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 56))
                    .foregroundColor(.blue)

                Text("Codex Adaptor")
                    .font(.title)
                    .fontWeight(.bold)

                Text(appVersion())
                    .font(.body)
                    .foregroundColor(.secondary)

                Text(L10n.t("codex_about_subtitle"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 40)
            .padding(.bottom, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func appVersion() -> String {
        if let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !ver.isEmpty {
            return ver
        }
        return "0.0.0"
    }
}
