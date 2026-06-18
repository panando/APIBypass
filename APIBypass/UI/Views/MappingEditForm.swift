import SwiftUI

struct MappingEditForm: View {
    @ObservedObject var configManager: ConfigManager
    let keychain: KeychainService

    // Basic info bindings
    @Binding var name: String
    @Binding var incomingModel: String
    @Binding var actualModel: String
    @Binding var selectedProviderId: UUID?
    @Binding var isEnabled: Bool

    // Parameter bindings
    @Binding var temperature: String
    @Binding var maxTokens: String
    @Binding var topP: String
    @Binding var frequencyPenalty: String
    @Binding var presencePenalty: String

    // Thinking bindings
    @Binding var thinkingOverrideEnabled: Bool
    @Binding var thinkingEnabled: Bool
    @Binding var thinkingBudget: String
    @Binding var thinkingProtocol: ThinkingConfig.ThinkingProtocol
    @Binding var thinkingEffort: String

    // Custom fields
    @Binding var customFields: [CustomField]
    @Binding var customFieldsEnabled: Bool

    // Focus control
    var focusIncomingModelTrigger: Int = 0

    @State private var showNewProviderSheet = false
    @State private var showThinkingProtocolHelp = false
    @FocusState private var isIncomingModelFocused: Bool
    private let l10n = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 12) {
            // Basic Info
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("basic_info"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    HStack {
                        Text(L10n.t("config_name"))
                            .frame(width: 100, alignment: .trailing)
                        TextField(L10n.t("config_name_placeholder"), text: $name)
                    }
                    HStack {
                        Text(L10n.t("incoming_model"))
                            .frame(width: 100, alignment: .trailing)
                        TextField(L10n.t("incoming_model_field"), text: $incomingModel)
                            .focused($isIncomingModelFocused)
                    }
                    HStack {
                        Text(L10n.t("actual_model"))
                            .frame(width: 100, alignment: .trailing)
                        TextField(L10n.t("actual_model_field"), text: $actualModel)
                    }
                    HStack {
                        Text(L10n.t("provider"))
                            .frame(width: 100, alignment: .trailing)
                        Picker("", selection: $selectedProviderId) {
                            ForEach(configManager.providers) { provider in
                                Text(provider.name).tag(provider.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(x: -8)

                        Button {
                            showNewProviderSheet = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                    }

                    if let pid = selectedProviderId,
                       configManager.providers.first(where: { $0.id == pid }) == nil {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(L10n.t("provider_deleted_warning"))
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(.leading, 108)
                    }

                    if let pid = selectedProviderId,
                       let provider = configManager.providers.first(where: { $0.id == pid }) {
                        HStack {
                            Text("")
                                .frame(width: 100, alignment: .trailing)
                            Text("\(L10n.t(provider.apiProvider == .openai ? "provider_type_openai" : "provider_type_anthropic")) · \(provider.baseURL.host ?? provider.baseURL.absoluteString)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Thinking Override
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.t("reasoning_override"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Toggle("", isOn: $thinkingOverrideEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .fixedSize()
                }

                Text(L10n.t("reasoning_hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    // Protocol picker
                    HStack {
                        Text(L10n.t("thinking_protocol"))
                            .frame(width: 120, alignment: .trailing)
                        Picker("", selection: $thinkingProtocol) {
                            ForEach(ThinkingConfig.ThinkingProtocol.allCases, id: \.self) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220, alignment: .leading)
                        .disabled(!thinkingOverrideEnabled)
                        Button {
                            showThinkingProtocolHelp.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showThinkingProtocolHelp) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.t("thinking_protocol_help_title"))
                                    .font(.headline)
                                Text(L10n.t("thinking_protocol_help_enable_thinking"))
                                    .font(.body)
                                Text(L10n.t("thinking_protocol_help_reasoning_effort"))
                                    .font(.body)
                                Text(L10n.t("thinking_protocol_help_anthropic_native"))
                                    .font(.body)
                                Text(L10n.t("thinking_protocol_help_none"))
                                    .font(.body)
                            }
                            .padding(12)
                            .frame(width: 360)
                        }
                        Spacer()
                    }

                    // Protocol-specific controls
                    switch thinkingProtocol {
                    case .enable_thinking:
                        HStack {
                            Text(L10n.t("enable_thinking"))
                            Spacer()
                            Toggle("", isOn: $thinkingEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .fixedSize()
                                .disabled(!thinkingOverrideEnabled)
                        }
                        if thinkingEnabled {
                            HStack {
                                Text(L10n.t("thinking_budget"))
                                    .frame(width: 120, alignment: .trailing)
                                TextField(L10n.t("thinking_budget_hint"), text: $thinkingBudget)
                                    .disabled(!thinkingOverrideEnabled)
                                Text(L10n.t("thinking_budget_eg"))
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    case .reasoning_effort:
                        HStack {
                            Text(L10n.t("enable_thinking"))
                            Spacer()
                            Toggle("", isOn: $thinkingEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .fixedSize()
                                .disabled(!thinkingOverrideEnabled)
                        }
                        if thinkingEnabled {
                            HStack {
                                Text(L10n.t("thinking_effort"))
                                    .frame(width: 120, alignment: .trailing)
                                Picker("", selection: $thinkingEffort) {
                                    Text("low").tag("low")
                                    Text("medium").tag("medium")
                                    Text("high").tag("high")
                                }
                                .labelsHidden()
                                .disabled(!thinkingOverrideEnabled)
                            }
                        }
                    case .anthropic_native:
                        HStack {
                            Text(L10n.t("enable_thinking"))
                            Spacer()
                            Toggle("", isOn: $thinkingEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .fixedSize()
                                .disabled(!thinkingOverrideEnabled)
                        }
                        if thinkingEnabled {
                            HStack {
                                Text(L10n.t("thinking_budget"))
                                    .frame(width: 120, alignment: .trailing)
                                TextField(L10n.t("thinking_budget_hint"), text: $thinkingBudget)
                                    .disabled(!thinkingOverrideEnabled)
                                Text(L10n.t("thinking_budget_eg"))
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    case .none:
                        Text(L10n.t("thinking_none_hint"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .opacity(thinkingOverrideEnabled ? 1.0 : 0.4)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Parameter Injection
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("param_injection"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    HStack {
                        Text(L10n.t("param_temperature"))
                            .frame(width: 120, alignment: .trailing)
                        TextField(L10n.t("temp_placeholder"), text: $temperature)
                    }
                    HStack {
                        Text(L10n.t("param_max_tokens"))
                            .frame(width: 120, alignment: .trailing)
                        TextField(L10n.t("max_tokens_placeholder"), text: $maxTokens)
                    }
                    HStack {
                        Text(L10n.t("param_top_p"))
                            .frame(width: 120, alignment: .trailing)
                        TextField(L10n.t("top_p_placeholder"), text: $topP)
                    }
                    HStack {
                        Text(L10n.t("param_frequency_penalty"))
                            .frame(width: 120, alignment: .trailing)
                        TextField(L10n.t("freq_penalty_placeholder"), text: $frequencyPenalty)
                    }
                    HStack {
                        Text(L10n.t("param_presence_penalty"))
                            .frame(width: 120, alignment: .trailing)
                        TextField(L10n.t("pres_penalty_placeholder"), text: $presencePenalty)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Custom Parameters
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.t("custom_params"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Toggle("", isOn: $customFieldsEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .fixedSize()
                }

                VStack(spacing: 8) {
                    HStack {
                        Button(action: {
                            customFields.append(CustomField(key: "", value: ""))
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                Text(L10n.t("add_field"))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!customFieldsEnabled)
                        Spacer()
                    }

                    if customFields.isEmpty {
                        Text(L10n.t("add_custom_hint"))
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(customFields.indices, id: \.self) { index in
                                HStack {
                                    TextField(L10n.t("field_name_placeholder"), text: $customFields[index].key)
                                        .frame(idealWidth: 140, maxWidth: .infinity)
                                        .disabled(!customFieldsEnabled)
                                    TextField(L10n.t("field_value_placeholder"), text: $customFields[index].value)
                                        .frame(idealWidth: 210, maxWidth: .infinity)
                                        .disabled(!customFieldsEnabled)
                                    Button(action: {
                                        customFields.remove(at: index)
                                    }) {
                                        Image(systemName: "minus.circle")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!customFieldsEnabled)
                                }
                            }
                        }
                    }
                }
                .opacity(customFieldsEnabled ? 1.0 : 0.4)

                Text(L10n.t("custom_hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .sheet(isPresented: $showNewProviderSheet) {
            NewProviderView(configManager: configManager, keychain: keychain) { newProvider in
                selectedProviderId = newProvider.id
            }
        }
        .onChange(of: focusIncomingModelTrigger) { _, _ in
            isIncomingModelFocused = true
        }
    }
}
