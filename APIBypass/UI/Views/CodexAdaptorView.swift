import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CodexRouterCore

// MARK: - Config Tab

private enum ConfigTab: String, CaseIterable, Identifiable {
    case server
    case logs

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
                    sidebarItem(tab: .logs, icon: "doc.text.magnifyingglass")
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
    @State private var modelIndexToDelete: Int?
    @State private var draftCustomModels: [CustomModelEntry] = []
    @State private var draggingCustomModelId: UUID?
    @State private var customModelDropTarget: CustomModelDropTarget?
    @State private var showReasoningInfo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Runtime Status
                cardSection(header: Label(L10n.t("codex_runtime_status"), systemImage: "power")) {
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
                    }
                }

                // Communication Protocol
                cardSection(header: Label(L10n.t("codex_wire_api"), systemImage: "arrow.triangle.swap")) {
                    Text(L10n.t("codex_wire_api_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker(L10n.t("codex_wire_api"), selection: $config.wireAPI) {
                        ForEach(CodexAdaptorConfig.WireAPI.allCases, id: \.self) { api in
                            Text(api.displayName).tag(api)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: config.wireAPI) { _, _ in saveConfig() }
                }

                // Proxy Server
                cardSection(header: Text(L10n.t("codex_proxy_server"))) {
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
                }

                // Reasoning Configuration
                reasoningSection

                // Custom Models
                customModelsSection

                // Codex Enhancements
                enhancementsCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .onAppear { loadConfig() }
        .onChange(of: portText) { _, newValue in
            if let portValue = Int(newValue), portValue > 0, portValue <= 65535 {
                config.port = portValue
                proxyURL = "http://127.0.0.1:\(portValue)/v1"
                saveConfig()
            }
        }
    }

    // MARK: - Card Section Helper

    @ViewBuilder
    private func cardSection<Header: View, Content: View>(
        header: Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header
                .font(.headline)
            content()
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
    }

    // MARK: - Enhancements Card

    private var enhancementsCard: some View {
        cardSection(header: Label(L10n.t("codex_enhancements"), systemImage: "wand.and.stars")) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("codex_plugin_entry_unlock")).fontWeight(.medium)
                    Text(L10n.t("codex_plugin_entry_unlock_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $config.cdpSettings.codexAppPluginEntryUnlock)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .onChange(of: config.cdpSettings.codexAppPluginEntryUnlock) { _, _ in
                saveConfig()
                Task { await codexAdaptor.pushInjectionSettings() }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("codex_marketplace_unlock")).fontWeight(.medium)
                    Text(L10n.t("codex_marketplace_unlock_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $config.cdpSettings.codexAppPluginMarketplaceUnlock)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .onChange(of: config.cdpSettings.codexAppPluginMarketplaceUnlock) { _, _ in
                saveConfig()
                Task { await codexAdaptor.pushInjectionSettings() }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("codex_force_plugin_install")).fontWeight(.medium)
                    Text(L10n.t("codex_force_plugin_install_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $config.cdpSettings.codexAppForcePluginInstall)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .onChange(of: config.cdpSettings.codexAppForcePluginInstall) { _, _ in
                saveConfig()
                Task { await codexAdaptor.pushInjectionSettings() }
            }
        }
    }

    // MARK: - Reasoning Section

    private var reasoningSection: some View {
        cardSection(header: Label(L10n.t("codex_reasoning"), systemImage: "brain.head.profile")) {
            // Toggle row
            HStack {
                Toggle("", isOn: $config.reasoningOverrideEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                Text(L10n.t("codex_override_reasoning"))
                Spacer()
                if config.reasoningOverrideEnabled {
                    HStack(spacing: 6) {
                        Button(L10n.t("codex_auto_detect")) {
                            inferReasoningConfig()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(configManager.providers.isEmpty)
                        Button {
                            showReasoningInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .popover(isPresented: $showReasoningInfo) {
                            reasoningInfoPopover
                        }
                    }
                }
            }

            if !config.reasoningOverrideEnabled {
                HStack(spacing: 4) {
                    Text(L10n.t("codex_reasoning_auto_footer"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        showReasoningInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .popover(isPresented: $showReasoningInfo) {
                        reasoningInfoPopover
                    }
                }
                .padding(.top, 8)
            }

            if config.reasoningOverrideEnabled {
                VStack(alignment: .leading, spacing: 12) {
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
        .onChange(of: supportsThinking) { _, _ in updateReasoningConfig() }
        .onChange(of: supportsEffort) { _, _ in updateReasoningConfig() }
        .onChange(of: thinkingParam) { _, _ in updateReasoningConfig() }
        .onChange(of: effortParam) { _, _ in updateReasoningConfig() }
        .onChange(of: effortValueMode) { _, _ in updateReasoningConfig() }
        .onChange(of: reasoningOutputFormat) { _, _ in updateReasoningConfig() }
        .onChange(of: config.reasoningOverrideEnabled) { _, _ in updateReasoningConfig() }
    }

    // MARK: - Reasoning Info Popover

    private var reasoningInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("codex_reasoning_info_title"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("codex_reasoning_info_basis"))
                    .fontWeight(.medium)
                Text(L10n.t("codex_reasoning_info_basis_desc"))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("codex_reasoning_info_supported"))
                    .fontWeight(.medium)
                Text(L10n.t("codex_reasoning_info_supported_list"))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("codex_reasoning_info_unmatched"))
                    .fontWeight(.medium)
                Text(L10n.t("codex_reasoning_info_unmatched_desc"))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: - Custom Models Section

    private var customModelsSection: some View {
        let handleWidth: CGFloat = 18
        let contextWidth: CGFloat = 100
        let actionWidth: CGFloat = 60

        return cardSection(header: Label(L10n.t("codex_custom_models"), systemImage: "cube.box")) {
            Text(L10n.t("codex_model_footer"))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 12) {
                    Spacer().frame(width: handleWidth)
                    Text(L10n.t("codex_model_alias"))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(L10n.t("codex_model_slug"))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(L10n.t("codex_context_window"))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)
                        .frame(width: contextWidth, alignment: .center)
                    Spacer().frame(width: actionWidth)
                }
                HStack(spacing: 12) {
                    Spacer().frame(width: handleWidth)
                    Text(L10n.t("codex_model_alias_desc"))
                        .font(.caption2).foregroundColor(.secondary.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(L10n.t("codex_model_slug_desc"))
                        .font(.caption2).foregroundColor(.secondary.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(L10n.t("codex_context_window_eg"))
                        .font(.caption2).foregroundColor(.secondary.opacity(0.8))
                        .frame(width: contextWidth, alignment: .center)
                    Spacer().frame(width: actionWidth)
                }
            }
            .padding(.bottom, 4)

            ForEach(draftCustomModels) { model in
                customModelRow(model)
            }

            Button {
                let firstMapping = CodexConfigBridge.availableMappings(from: configManager).first
                let entry = CustomModelEntry(
                    alias: "",
                    modelMappingId: firstMapping?.id ?? UUID(),
                    contextWindow: nil
                )
                draftCustomModels.append(entry)
            } label: {
                Label(L10n.t("codex_add_model"), systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            if hasUnsavedModelChanges {
                Divider()
                    .padding(.vertical, 4)
                HStack(spacing: 8) {
                    Button(L10n.t("save")) { saveCustomModels() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button(L10n.t("cancel")) { cancelCustomModels() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .confirmationDialog(
            L10n.t("confirm_delete"),
            isPresented: Binding(
                get: { modelIndexToDelete != nil },
                set: { if !$0 { modelIndexToDelete = nil } }
            )
        ) {
            Button(L10n.t("delete"), role: .destructive) {
                if let idx = modelIndexToDelete {
                    draftCustomModels.remove(at: idx)
                    modelIndexToDelete = nil
                    saveCustomModels()
                }
            }
            Button(L10n.t("cancel"), role: .cancel) { modelIndexToDelete = nil }
        } message: {
            Text(L10n.t("confirm_delete_generic"))
        }
    }

    // MARK: - Helpers

    private func customModelRow(_ model: CustomModelEntry) -> some View {
        let canDrag = draftCustomModels.count > 1
        let handleWidth: CGFloat = 18
        let contextWidth: CGFloat = 100
        let actionWidth: CGFloat = 60

        return VStack(spacing: 0) {
            customModelDropLine(for: model.id, position: .before)

            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(canDrag ? .secondary : .secondary.opacity(0.35))
                    .frame(width: handleWidth)
                    .contentShape(Rectangle())
                    .onDrag {
                        draggingCustomModelId = model.id
                        return NSItemProvider(object: model.id.uuidString as NSString)
                    }
                    .disabled(!canDrag)

                TextField("", text: customModelBinding(for: model.id, keyPath: \.alias))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity)

                Picker("", selection: customModelBinding(for: model.id, keyPath: \.modelMappingId)) {
                    let mappingsWithProvider = CodexConfigBridge.availableMappingsWithProvider(from: configManager)
                    let chatMappings = mappingsWithProvider.filter { $0.providerType != .responses }
                    let responsesMappings = mappingsWithProvider.filter { $0.providerType == .responses }

                    if !chatMappings.isEmpty {
                        Section(L10n.t("provider_group_chat_completions")) {
                            ForEach(chatMappings) { item in
                                Text(item.mapping.incomingModel).tag(item.mapping.id)
                            }
                        }
                    }
                    if !responsesMappings.isEmpty {
                        Section(L10n.t("provider_group_responses")) {
                            ForEach(responsesMappings) { item in
                                Text(item.mapping.incomingModel).tag(item.mapping.id)
                            }
                        }
                    }
                }
                .labelsHidden()
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity)

                TextField(
                    L10n.t("codex_context_window_eg"),
                    text: Binding(
                        get: {
                            draftCustomModels.first(where: { $0.id == model.id })?.contextWindow.map { String($0) } ?? ""
                        },
                        set: { value in
                            guard let index = draftCustomModels.firstIndex(where: { $0.id == model.id }) else { return }
                            draftCustomModels[index].contextWindow = UInt64(value)
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(width: contextWidth)

                Button {
                    modelIndexToDelete = draftCustomModels.firstIndex(where: { $0.id == model.id })
                } label: {
                    Image(systemName: "trash")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(width: actionWidth)
            }
            .opacity(draggingCustomModelId == model.id ? 0.6 : 1)
            .onDrop(of: [.text], delegate: CustomModelDropDelegate(
                targetId: model.id,
                models: draftCustomModels,
                draggingId: $draggingCustomModelId,
                dropTarget: $customModelDropTarget,
                move: moveCustomModel
            ))

            customModelDropLine(for: model.id, position: .after)
        }
    }

    private func customModelDropLine(for id: UUID, position: CustomModelDropPosition) -> some View {
        Rectangle()
            .fill(customModelDropTarget == CustomModelDropTarget(id: id, position: position) ? Color.accentColor : Color.clear)
            .frame(height: 2)
            .padding(.leading, 30)
    }

    private func customModelBinding<Value>(for id: UUID, keyPath: WritableKeyPath<CustomModelEntry, Value>) -> Binding<Value> {
        Binding(
            get: {
                draftCustomModels.first(where: { $0.id == id })![keyPath: keyPath]
            },
            set: { value in
                guard let index = draftCustomModels.firstIndex(where: { $0.id == id }) else { return }
                draftCustomModels[index][keyPath: keyPath] = value
            }
        )
    }

    private func moveCustomModel(sourceId: UUID, targetId: UUID, position: CustomModelDropPosition) {
        guard sourceId != targetId,
              let sourceIndex = draftCustomModels.firstIndex(where: { $0.id == sourceId }),
              let targetIndex = draftCustomModels.firstIndex(where: { $0.id == targetId }) else { return }

        let model = draftCustomModels.remove(at: sourceIndex)
        var insertionIndex = draftCustomModels.firstIndex(where: { $0.id == targetId }) ?? targetIndex
        if position == .after {
            insertionIndex += 1
        }
        draftCustomModels.insert(model, at: insertionIndex)
    }

    private func loadConfig() {
        Task {
            config = await CodexAdaptorConfigStore.shared.load()
            portText = String(config.port)
            proxyURL = "http://127.0.0.1:\(config.port)/v1"
            draftCustomModels = config.customModels

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
            updateReasoningConfig()
        }
    }

    private var hasUnsavedModelChanges: Bool {
        draftCustomModels != config.customModels
    }

    private func saveCustomModels() {
        config.customModels = draftCustomModels
        saveConfig()
    }

    private func cancelCustomModels() {
        draftCustomModels = config.customModels
    }
}

private enum CustomModelDropPosition: Equatable {
    case before
    case after
}

private struct CustomModelDropTarget: Equatable {
    let id: UUID
    let position: CustomModelDropPosition
}

private struct CustomModelDropDelegate: DropDelegate {
    let targetId: UUID
    let models: [CustomModelEntry]
    @Binding var draggingId: UUID?
    @Binding var dropTarget: CustomModelDropTarget?
    let move: (UUID, UUID, CustomModelDropPosition) -> Void

    func dropEntered(info: DropInfo) {
        updateDropTarget(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropTarget(info: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceId = draggingId,
              let target = dropTarget,
              target.id == targetId else {
            draggingId = nil
            dropTarget = nil
            return false
        }

        move(sourceId, target.id, target.position)
        draggingId = nil
        dropTarget = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if dropTarget?.id == targetId {
            dropTarget = nil
        }
    }

    private func updateDropTarget(info: DropInfo) {
        guard let draggingId,
              draggingId != targetId,
              models.contains(where: { $0.id == draggingId }) else { return }

        let position: CustomModelDropPosition = info.location.y < 16 ? .before : .after
        dropTarget = CustomModelDropTarget(id: targetId, position: position)
    }
}

// MARK: - Log Viewer Tab

private struct CodexLogViewerTab: View {
    @State private var entries: [LogEntry] = []
    @State private var autoScroll = true
    @State private var filterText = ""
    @State private var copyConfirmation = false

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                TextField(L10n.t("codex_filter"), text: $filterText)
                    .textFieldStyle(.roundedBorder)
                Toggle(L10n.t("codex_auto_scroll"), isOn: $autoScroll)

                Button(L10n.t("codex_copy_all")) { copyAll() }
                Button(L10n.t("codex_export_logs")) { exportLogs() }
                Button(L10n.t("codex_clear_logs")) {
                    CodexLogStore.shared.clear()
                    entries = []
                }
            }
            .padding(8)

            Divider()

            // Log list
            ScrollViewReader { proxy in
                List(filteredEntries) { entry in
                    CodexLogEntryRow(entry: entry)
                        .id(entry.id)
                }
                .onReceive(timer) { _ in
                    entries = CodexLogStore.shared.snapshot()
                }
                .onChange(of: entries.count) { _, _ in
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
        if filterText.isEmpty { return entries }
        return entries.filter { $0.message.localizedCaseInsensitiveContains(filterText) }
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
                let text = formatEntries(entries)
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


