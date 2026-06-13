import SwiftUI

enum HelpSection: String, CaseIterable, Identifiable {
    case quickStart, menuBar, modelMapping, parameterInjection, launcher, bypassMode, codexAdaptor, settings, faq

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .quickStart: return "help_quick_start"
        case .menuBar: return "help_menu_bar"
        case .modelMapping: return "help_model_mapping"
        case .parameterInjection: return "help_parameter_injection"
        case .launcher: return "help_launcher"
        case .bypassMode: return "help_bypass_mode"
        case .codexAdaptor: return "help_codex_adaptor"
        case .settings: return "help_settings"
        case .faq: return "help_faq"
        }
    }
}

struct HelpView: View {
    @State private var selectedSection: HelpSection = .quickStart
    private let l10n = LocalizationManager.shared

    var body: some View {
        NavigationSplitView {
            List(HelpSection.allCases, selection: $selectedSection) { section in
                Text(L10n.t(section.titleKey))
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180, idealWidth: 200)
        } detail: {
            ScrollView {
                content(for: selectedSection)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func content(for section: HelpSection) -> some View {
        switch section {
        case .quickStart:
            quickStartContent
        case .menuBar:
            menuBarContent
        case .modelMapping:
            modelMappingContent
        case .parameterInjection:
            parameterInjectionContent
        case .launcher:
            launcherContent
        case .bypassMode:
            bypassModeContent
        case .codexAdaptor:
            codexAdaptorContent
        case .settings:
            settingsContent
        case .faq:
            faqContent
        }
    }

    private var quickStartContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("help_quick_start_title"))
                .font(.title2.bold())

            Text(L10n.t("help_quick_start_desc"))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. " + L10n.t("help_quick_start_step1"))
                Text("2. " + L10n.t("help_quick_start_step2"))
                Text("3. " + L10n.t("help_quick_start_step3"))
            }
            .foregroundColor(.secondary)

            Text(L10n.t("help_quick_start_note"))
                .foregroundColor(.secondary)
        }
    }

    private var menuBarContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("help_menu_bar"))
                .font(.title2.bold())

            Text(L10n.t("help_menu_bar_desc"))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                bullet(L10n.t("help_menu_status"))
                bullet(L10n.t("help_menu_bypass"))
                bullet(L10n.t("help_menu_configure"))
                bullet(L10n.t("help_menu_settings"))
                bullet(L10n.t("help_menu_launcher"))
                bullet(L10n.t("help_menu_control"))
                bullet(L10n.t("help_menu_quit"))
                bullet(L10n.t("help_menu_help"))
            }
        }
    }

    private var modelMappingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("help_model_mapping_title"))
                .font(.title2.bold())

            Text(L10n.t("help_model_mapping_desc"))
                .foregroundColor(.secondary)

            Text(L10n.t("help_model_mapping_fields"))
                .foregroundColor(.secondary)

            Text(L10n.t("help_model_mapping_reasoning"))
                .foregroundColor(.secondary)
        }
    }

    private var parameterInjectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("help_param_injection_title"))
                .font(.title2.bold())

            Text(L10n.t("help_param_injection_desc"))
                .foregroundColor(.secondary)

            Text(L10n.t("help_custom_params"))
                .foregroundColor(.secondary)
        }
    }

    private var launcherContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("help_launcher_title"))
                .font(.title2.bold())

            Text(L10n.t("help_launcher_desc"))
                .foregroundColor(.secondary)

            Text(L10n.t("help_launcher_features"))
                .foregroundColor(.secondary)
        }
    }

    private var bypassModeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("help_bypass_title"))
                .font(.title2.bold())

            Text(L10n.t("help_bypass_desc"))
                .foregroundColor(.secondary)

            Text(L10n.t("help_bypass_note"))
                .foregroundColor(.orange)
        }
    }

    private var codexAdaptorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("help_codex_adaptor"))
                .font(.title2.bold())

            Text("Codex Adaptor is a Responses API proxy for OpenAI Codex CLI. It translates Codex's Responses API calls into Chat Completions format, allowing you to use any OpenAI-compatible provider with Codex.")
                .foregroundColor(.secondary)

            Text("How to Use")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                bullet("Open \"Codex Adaptor\" from the menu bar")
                bullet("Click \"Start\" to launch the proxy service on port 15721")
                bullet("Configure Codex CLI to use http://127.0.0.1:15721/v1 as its API base URL")
            }

            Text("Configuration")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                bullet("Communication Protocol: Choose between Chat Completions or Responses API wire format")
                bullet("Reasoning Configuration: Auto-detect or manually set thinking/effort parameters for different providers")
                bullet("Custom Models: Define model aliases that map to your APIBypass model mappings")
            }

            Text("CDP Enhancements")
                .font(.headline)

            Text("Chrome DevTools Protocol injection for the Codex Electron app. Enables plugin entry unlock, marketplace unlock, and force plugin install features.")
                .foregroundColor(.secondary)
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("help_settings_title"))
                .font(.title2.bold())

            Text(L10n.t("help_settings_desc"))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                bullet(L10n.t("help_settings_lang"))
                bullet(L10n.t("help_settings_port"))
            }
        }
    }

    private var faqContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("help_faq"))
                .font(.title2.bold())

            faqItem(L10n.t("help_faq_q1"), L10n.t("help_faq_a1"))
            faqItem(L10n.t("help_faq_q2"), L10n.t("help_faq_a2"))
            faqItem(L10n.t("help_faq_q3"), L10n.t("help_faq_a3"))
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(.secondary)
    }

    private func faqItem(_ question: String, _ answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.headline)
            Text(answer)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    HelpView()
        .frame(width: 700, height: 500)
}
