import SwiftUI

enum HelpSection: String, CaseIterable, Identifiable {
    case quickStart, menuBar, modelMapping, parameterInjection, thinkingProtocol, bypassMode, launcher, codexAdaptor, customModels, settings, faq

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .quickStart: return "help_quick_start"
        case .menuBar: return "help_menu_bar"
        case .modelMapping: return "help_model_mapping"
        case .parameterInjection: return "help_parameter_injection"
        case .thinkingProtocol: return "help_thinking_protocol"
        case .bypassMode: return "help_bypass_mode"
        case .launcher: return "help_launcher"
        case .codexAdaptor: return "help_codex_adaptor"
        case .customModels: return "help_custom_models"
        case .settings: return "help_settings"
        case .faq: return "help_faq"
        }
    }
}

struct HelpView: View {
    @State private var selectedSection: HelpSection = .quickStart
    @State private var sidebarVisible: Bool = true
    private let l10n = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                List(HelpSection.allCases, selection: $selectedSection) { section in
                    Text(L10n.t(section.titleKey))
                        .tag(section)
                }
                .listStyle(.sidebar)
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)
            }

            ScrollView {
                content(for: selectedSection)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation {
                        sidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
            }
        }
    }

    @ViewBuilder
    private func content(for section: HelpSection) -> some View {
        switch section {
        case .quickStart:         quickStartContent
        case .menuBar:            menuBarContent
        case .modelMapping:       modelMappingContent
        case .parameterInjection: parameterInjectionContent
        case .thinkingProtocol:   thinkingProtocolContent
        case .bypassMode:         bypassModeContent
        case .launcher:           launcherContent
        case .codexAdaptor:       codexAdaptorContent
        case .customModels:       customModelsContent
        case .settings:           settingsContent
        case .faq:                faqContent
        }
    }

    // MARK: - Sections

    private var quickStartContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle(L10n.t("help_quick_start_title"))
            body(L10n.t("help_quick_start_desc"))

            group(L10n.t("help_quick_start_features_title")) {
                bulletList([
                    L10n.t("help_quick_start_feature_mapping"),
                    L10n.t("help_quick_start_feature_params"),
                    L10n.t("help_quick_start_feature_thinking"),
                    L10n.t("help_quick_start_feature_namefix"),
                    L10n.t("help_quick_start_feature_bypass"),
                    L10n.t("help_quick_start_feature_codex"),
                    L10n.t("help_quick_start_feature_custom_models"),
                    L10n.t("help_quick_start_feature_launcher"),
                    L10n.t("help_quick_start_feature_trace"),
                    L10n.t("help_quick_start_feature_bilingual")
                ])
            }

            group(L10n.t("help_quick_start_steps_title")) {
                numberedList([
                    L10n.t("help_quick_start_step1"),
                    L10n.t("help_quick_start_step2"),
                    L10n.t("help_quick_start_step3")
                ])
            }

            note(L10n.t("help_quick_start_note"))
        }
    }

    private var menuBarContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle(L10n.t("help_menu_bar"))
            body(L10n.t("help_menu_bar_desc"))
            bulletList([
                L10n.t("help_menu_status"),
                L10n.t("help_menu_control"),
                L10n.t("help_menu_codex_control"),
                L10n.t("help_menu_bypass"),
                L10n.t("help_menu_launcher"),
                L10n.t("help_menu_codex_window"),
                L10n.t("help_menu_configure"),
                L10n.t("help_menu_settings"),
                L10n.t("help_menu_help"),
                L10n.t("help_menu_about"),
                L10n.t("help_menu_quit")
            ])
        }
    }

    private var modelMappingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle(L10n.t("help_model_mapping_title"))
            body(L10n.t("help_model_mapping_desc"))
            group(L10n.t("help_model_mapping_provider_title")) {
                body(L10n.t("help_model_mapping_provider_desc"))
            }
            group(L10n.t("help_model_mapping_fields_title")) {
                body(L10n.t("help_model_mapping_fields"))
                body(L10n.t("help_model_mapping_reasoning"))
            }
            group(L10n.t("help_model_mapping_enable_title")) {
                body(L10n.t("help_model_mapping_enable_desc"))
            }
            group(L10n.t("help_model_mapping_name_fix_title")) {
                body(L10n.t("help_model_mapping_name_fix"))
            }
            group(L10n.t("help_model_mapping_stream_usage_title")) {
                body(L10n.t("help_model_mapping_stream_usage_desc"))
            }
        }
    }

    private var parameterInjectionContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle(L10n.t("help_param_injection_title"))
            group(L10n.t("help_group_standard_params")) {
                body(L10n.t("help_param_injection_desc"))
            }
            group(L10n.t("custom_params")) {
                body(L10n.t("help_custom_params"))
            }
        }
    }

    private var thinkingProtocolContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle(L10n.t("help_thinking_protocol_title"))
            body(L10n.t("help_thinking_protocol_desc"))
            group(L10n.t("help_group_protocol_options")) {
                bulletList([
                    L10n.t("help_thinking_protocol_opt_enable"),
                    L10n.t("help_thinking_protocol_opt_anthropic"),
                    L10n.t("help_thinking_protocol_opt_none")
                ])
            }
            group(L10n.t("thinking_effort")) {
                body(L10n.t("help_thinking_protocol_effort"))
            }
            note(L10n.t("help_thinking_protocol_note"))
        }
    }

    private var bypassModeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle(L10n.t("help_bypass_title"))
            body(L10n.t("help_bypass_desc"))
            note(L10n.t("help_bypass_note"))
        }
    }

    private var launcherContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle(L10n.t("help_launcher_title"))
            body(L10n.t("help_launcher_desc"))
            group(L10n.t("help_launcher_features_title")) {
                bulletList([
                    L10n.t("help_launcher_feature_terminal"),
                    L10n.t("help_launcher_feature_role_models"),
                    L10n.t("help_launcher_feature_effort"),
                    L10n.t("help_launcher_feature_custom_env"),
                    L10n.t("help_launcher_feature_cache"),
                    L10n.t("help_launcher_feature_rectifier"),
                    L10n.t("help_launcher_feature_templates"),
                    L10n.t("help_launcher_feature_keychain")
                ])
            }
            group(L10n.t("help_launcher_workflow_title")) {
                numberedList([
                    L10n.t("help_launcher_workflow_1"),
                    L10n.t("help_launcher_workflow_2"),
                    L10n.t("help_launcher_workflow_3"),
                    L10n.t("help_launcher_workflow_4")
                ])
            }
            note(L10n.t("help_launcher_note"))
        }
    }

    private var codexAdaptorContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle(L10n.t("help_codex_adaptor_title"))
            body(L10n.t("help_codex_adaptor_desc"))
            group(L10n.t("help_codex_usage_title")) {
                numberedList([
                    L10n.t("help_codex_usage_1"),
                    L10n.t("help_codex_usage_2"),
                    L10n.t("help_codex_usage_3")
                ])
                note(L10n.t("help_codex_usage_note"))
            }
            group(L10n.t("help_codex_config_title")) {
                bulletList([
                    L10n.t("help_codex_config_1"),
                    L10n.t("help_codex_config_2"),
                    L10n.t("help_codex_config_3"),
                    L10n.t("help_codex_config_4"),
                    L10n.t("help_codex_config_5")
                ])
            }
            group(L10n.t("help_codex_autodetect_title")) {
                body(L10n.t("help_codex_autodetect_desc"))
            }
            group(L10n.t("help_codex_logs_title")) {
                body(L10n.t("help_codex_logs_desc"))
            }
            group(L10n.t("help_codex_cdp_title")) {
                body(L10n.t("help_codex_cdp_desc"))
            }
        }
    }

    private var customModelsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle(L10n.t("help_custom_models_title"))
            body(L10n.t("help_custom_models_desc"))
            group {
                bulletList([
                    L10n.t("help_custom_models_alias"),
                    L10n.t("help_custom_models_source"),
                    L10n.t("help_custom_models_ctx")
                ])
            }
            body(L10n.t("help_custom_models_note"))
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle(L10n.t("help_settings_title"))
            body(L10n.t("help_settings_desc"))
            bulletList([
                L10n.t("help_settings_lang"),
                L10n.t("help_settings_port"),
                L10n.t("help_settings_trace_log")
            ])
        }
    }

    private var faqContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle(L10n.t("help_faq"))
            faqItem(L10n.t("help_faq_q1"), L10n.t("help_faq_a1"))
            faqItem(L10n.t("help_faq_q2"), L10n.t("help_faq_a2"))
            faqItem(L10n.t("help_faq_q3"), L10n.t("help_faq_a3"))
            faqItem(L10n.t("help_faq_q4"), L10n.t("help_faq_a4"))
            faqItem(L10n.t("help_faq_q5"), L10n.t("help_faq_a5"))
            faqItem(L10n.t("help_faq_q6"), L10n.t("help_faq_a6"))
            faqItem(L10n.t("help_faq_q7"), L10n.t("help_faq_a7"))
        }
    }

    // MARK: - Typography helpers

    /// 强调：章节大标题（大、粗、黑）
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title2.bold())
            .foregroundStyle(.primary)
            .padding(.bottom, 2)
    }

    /// 弱化：正文段落（灰）
    private func body(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 弱化：补充说明（灰、小）
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                bullet(item)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            featureText(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 拆分「名称 — 说明」格式：名称加粗，说明保持常规。
    /// 不含 " — " 时原样返回。
    private func featureText(_ text: String) -> Text {
        if let range = text.range(of: " — ") {
            let name = String(text[..<range.lowerBound])
            let rest = String(text[range.lowerBound...])
            return Text(name).bold() + Text(rest)
        }
        return Text(text)
    }

    private func numberedList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(item)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 子问题分组：标题强调（粗、黑），内容弱化（灰），整体带外框
    private func group<S: View>(_ title: String? = nil, @ViewBuilder content: () -> S) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    private func faqItem(_ question: String, _ answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(answer)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HelpView()
        .frame(width: 700, height: 500)
}
