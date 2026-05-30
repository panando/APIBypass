import SwiftUI

struct NewMappingView: View {
    let configManager: ConfigManager
    let keychain: KeychainService
    var defaultProviderId: UUID?
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var l10n = LocalizationManager.shared

    @State private var name = "New Config"
    @State private var incomingModel = ""
    @State private var actualModel = ""
    @State private var selectedProviderId: UUID?
    @State private var showNewProviderSheet = false

    // Parameters
    @State private var temperature = ""
    @State private var maxTokens = ""
    @State private var topP = ""
    @State private var frequencyPenalty = ""
    @State private var presencePenalty = ""
    @State private var thinkingEnabled = false
    @State private var thinkingBudget = ""
    @State private var thinkingOverrideEnabled = false

    // Custom fields
    @State private var customFields: [CustomField] = []
    @State private var showDuplicateModelAlert = false
    @State private var focusIncomingModelTrigger = 0
    @FocusState private var isIncomingModelFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(L10n.t("new_model_mapping"))
                    .font(.headline)
                    .padding(.top, 8)

                basicInfoSection
                paramInjectionSection
                thinkingSection
                customParamsSection
                actionButtons
            }
            .padding()
        }
        .frame(width: 500, height: 700)
        .sheet(isPresented: $showNewProviderSheet) {
            NewProviderView(configManager: configManager, keychain: keychain) { newProvider in
                selectedProviderId = newProvider.id
            }
        }
        .onAppear {
            if selectedProviderId == nil {
                selectedProviderId = defaultProviderId
            }
        }
        .alert(L10n.t("duplicate_model_title"), isPresented: $showDuplicateModelAlert) {
            Button(L10n.t("ok"), role: .cancel) { }
        } message: {
            Text(L10n.t("duplicate_model_msg"))
        }
        .onChange(of: focusIncomingModelTrigger) { _, _ in
            isIncomingModelFocused = true
        }
    }

    @ViewBuilder
    private var basicInfoSection: some View {
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
                    TextField(L10n.t("incoming_model_placeholder"), text: $incomingModel)
                        .focused($isIncomingModelFocused)
                }
                HStack {
                    Text(L10n.t("actual_model"))
                        .frame(width: 100, alignment: .trailing)
                    TextField(L10n.t("actual_model_placeholder"), text: $actualModel)
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
                   let provider = configManager.findProvider(for: pid) {
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
    }

    @ViewBuilder
    private var paramInjectionSection: some View {
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
    }

    @ViewBuilder
    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("reasoning_override"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $thinkingOverrideEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Text(L10n.t("reasoning_hint"))
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                HStack {
                    Text(L10n.t("enable_thinking"))
                    Spacer()
                    Toggle("", isOn: $thinkingEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!thinkingOverrideEnabled)
                }
                if thinkingEnabled,
                   let pid = selectedProviderId,
                   let provider = configManager.findProvider(for: pid),
                   provider.apiProvider == .anthropic {
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
            }
            .opacity(thinkingOverrideEnabled ? 1.0 : 0.4)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var customParamsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("custom_params"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    customFields.append(CustomField(key: "", value: ""))
                }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
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
                                .frame(width: 120)
                            TextField(L10n.t("field_value_placeholder"), text: $customFields[index].value)
                            Button(action: {
                                customFields.remove(at: index)
                            }) {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text(L10n.t("custom_hint"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            Button(L10n.t("cancel")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(L10n.t("create")) {
                createMapping()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(incomingModel.isEmpty || actualModel.isEmpty || selectedProviderId == nil)
        }
        .padding(.bottom, 8)
    }

    private func createMapping() {
        guard let providerId = selectedProviderId else { return }

        // Check for duplicate incoming model name
        let duplicateExists = configManager.mappings.contains { $0.incomingModel.lowercased() == incomingModel.lowercased() }
        if duplicateExists {
            showDuplicateModelAlert = true
            focusIncomingModelTrigger += 1
            return
        }

        let mapping = ModelMapping(
            name: name,
            incomingModel: incomingModel,
            actualModel: actualModel,
            providerConfigId: providerId,
            parameters: buildParameters()
        )

        configManager.add(mapping)
        dismiss()
    }

    private func buildParameters() -> InjectedParameters {
        let temp = Double(temperature)
        let tokens = Int(maxTokens)
        let topPValue = Double(topP)
        let freqPenalty = Double(frequencyPenalty)
        let presPenalty = Double(presencePenalty)

        let thinking = ThinkingConfig(
            enabled: thinkingEnabled,
            budgetTokens: thinkingEnabled ? Int(thinkingBudget) : nil
        )

        let customFieldsDict: [String: String]? = customFields.isEmpty
            ? nil
            : Dictionary(uniqueKeysWithValues: customFields.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) })

        return InjectedParameters(
            temperature: temp,
            maxTokens: tokens,
            topP: topPValue,
            frequencyPenalty: freqPenalty,
            presencePenalty: presPenalty,
            thinking: thinking,
            thinkingOverrideEnabled: thinkingOverrideEnabled,
            customFields: customFieldsDict,
            customFieldsEnabled: customFields.isEmpty ? nil : true
        )
    }
}
