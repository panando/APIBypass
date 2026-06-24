import SwiftUI

extension View {
    func cardSectionStyle() -> some View {
        self
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
    }
}

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
    @Binding var thinkingProtocol: ThinkingConfig.ThinkingProtocol
    @Binding var thinkingEffort: String

    // Custom fields
    @Binding var customFields: [CustomField]
    @Binding var customFieldsEnabled: Bool

    // Focus control
    var focusIncomingModelTrigger: Int = 0

    @State private var showNewProviderSheet = false
    @FocusState private var isIncomingModelFocused: Bool
    private let l10n = LocalizationManager.shared

    // MARK: - Parameter Visibility Helpers

    /// 当前选择的 Provider 的 API 格式
    private var currentAPIProvider: APIProvider? {
        guard let pid = selectedProviderId,
              let provider = configManager.providers.first(where: { $0.id == pid }) else {
            return nil
        }
        return provider.apiProvider
    }

    /// 当前模型的能力档案
    private var modelProfile: ModelCapabilityProfile? {
        let model = actualModel.isEmpty ? incomingModel : actualModel
        return ModelCapabilityRegistry.findProfile(for: model)
    }

    /// 是否为未知模型
    private var isUnknownModel: Bool {
        let model = actualModel.isEmpty ? incomingModel : actualModel
        return !model.isEmpty && ModelCapabilityRegistry.findProfile(for: model) == nil
    }

    /// 计算参数可见性
    private func visibility(for parameter: InjectedParameter) -> ParameterVisibility {
        guard let apiProvider = currentAPIProvider else {
            return .supported  // 未选择 Provider 时显示所有参数
        }
        return ParameterVisibilityCalculator.visibility(
            for: parameter,
            modelProfile: modelProfile,
            apiProvider: apiProvider,
            thinkingEnabled: thinkingEnabled
        )
    }

    /// 计算思考模式可见性
    private var thinkingSectionVisibility: ThinkingVisibility {
        guard let apiProvider = currentAPIProvider else {
            return .hidden
        }
        return ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: modelProfile,
            apiProvider: apiProvider
        )
    }

    private var thinkingModelsKey: String {
        switch thinkingProtocol {
        case .enableThinking: return "thinking_models_enable_thinking"
        case .thinkingType: return "thinking_models_anthropic_native"
        case .reasoningEffort: return "thinking_models_none"
        }
    }

    /// 根据模型档案推断推荐的协议
    private var recommendedProtocol: ThinkingConfig.ThinkingProtocol? {
        guard let profile = modelProfile else { return nil }
        if profile.nativeParameters.contains(.thinkingType) {
            return .thinkingType
        } else if profile.nativeParameters.contains(.reasoningEffort) {
            return .reasoningEffort
        } else if profile.nativeParameters.contains(.thinkingBudget) {
            return .enableThinking
        }
        return nil
    }

    /// 当前选择的协议是否与推荐的协议不匹配
    private var isProtocolMismatch: Bool {
        guard let recommended = recommendedProtocol else { return false }
        return thinkingProtocol != recommended
    }

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
                        Text("\(L10n.t(provider.apiProvider == .openai ? "provider_type_openai" : "provider_type_anthropic")) · \(provider.baseURL.host ?? provider.baseURL.absoluteString)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .cardSectionStyle()

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

                if thinkingOverrideEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        // Thinking visibility indicator
                        switch thinkingSectionVisibility {
                        case .hidden:
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text(L10n.t("thinking_not_supported"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        case .visibleAndForced:
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.orange)
                                Text(L10n.t("thinking_always_on"))
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        case .visibleAndToggleable:
                            // Protocol picker — subheader style + left-aligned
                            HStack {
                                Text(L10n.t("thinking_protocol"))
                                    .fontWeight(.medium)
                                Spacer()
                                Picker("", selection: $thinkingProtocol) {
                                    ForEach(ThinkingConfig.ThinkingProtocol.allCases, id: \.self) { p in
                                        Text(p.displayName).tag(p)
                                    }
                                }
                                .labelsHidden()
                                .fixedSize()
                            }
                            Text(L10n.t(thinkingModelsKey))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            // Protocol mismatch warning
                            if isProtocolMismatch, let recommended = recommendedProtocol {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("\(L10n.t("protocol_mismatch_warning")) \(recommended.displayName)")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }

                            // Protocol-specific controls
                            switch thinkingProtocol {
                            case .enableThinking:
                                HStack {
                                    Text(L10n.t("enable_thinking"))
                                    Spacer()
                                    Toggle("", isOn: $thinkingEnabled)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                        .fixedSize()
                                }
                            case .thinkingType:
                                HStack {
                                    Text(L10n.t("enable_thinking"))
                                    Spacer()
                                    Toggle("", isOn: $thinkingEnabled)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                        .fixedSize()
                                }
                            case .reasoningEffort:
                                HStack {
                                    Text(L10n.t("thinking_effort"))
                                    TextField(L10n.t("thinking_effort_hint"), text: $thinkingEffort)
                                }
                            }
                        }
                    }
                }
            }
            .cardSectionStyle()

            // Parameter Injection
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.t("param_injection"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if isUnknownModel {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(L10n.t("unknown_model_warning"))
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                VStack(spacing: 8) {
                    // Temperature
                    parameterRow(
                        label: L10n.t("param_temperature"),
                        placeholder: L10n.t("temp_placeholder"),
                        text: $temperature,
                        visibility: visibility(for: .temperature)
                    )

                    // Max Tokens
                    parameterRow(
                        label: L10n.t("param_max_tokens"),
                        placeholder: L10n.t("max_tokens_placeholder"),
                        text: $maxTokens,
                        visibility: visibility(for: .maxTokens)
                    )

                    // Top P
                    parameterRow(
                        label: L10n.t("param_top_p"),
                        placeholder: L10n.t("top_p_placeholder"),
                        text: $topP,
                        visibility: visibility(for: .topP)
                    )

                    // Frequency Penalty
                    parameterRow(
                        label: L10n.t("param_frequency_penalty"),
                        placeholder: L10n.t("freq_penalty_placeholder"),
                        text: $frequencyPenalty,
                        visibility: visibility(for: .frequencyPenalty)
                    )

                    // Presence Penalty
                    parameterRow(
                        label: L10n.t("param_presence_penalty"),
                        placeholder: L10n.t("pres_penalty_placeholder"),
                        text: $presencePenalty,
                        visibility: visibility(for: .presencePenalty)
                    )
                }
            }
            .cardSectionStyle()

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

                if customFieldsEnabled {
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
                                        TextField(L10n.t("field_value_placeholder"), text: $customFields[index].value)
                                            .frame(idealWidth: 210, maxWidth: .infinity)
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
                    }

                    Text(L10n.t("custom_hint"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .cardSectionStyle()
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

    // MARK: - Helper Views

    /// 根据可见性状态显示参数行
    @ViewBuilder
    private func parameterRow(
        label: String,
        placeholder: String,
        text: Binding<String>,
        visibility: ParameterVisibility
    ) -> some View {
        switch visibility {
        case .supported:
            HStack {
                Text(label)
                    .frame(width: 120, alignment: .trailing)
                TextField(placeholder, text: text)
            }
        case .disabledWithReason(let reason):
            HStack {
                Text(label)
                    .frame(width: 120, alignment: .trailing)
                    .foregroundColor(.secondary)
                Text(reason)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
            .opacity(0.6)
        case .hidden:
            EmptyView()
        }
    }
}
