import SwiftUI

/// Provider 详情页的环境变量配置卡片
struct EnvironmentVariablesCard: View {
    @Binding var provider: ProviderConfig
    @ObservedObject var configManager: ConfigManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            descriptionView
            Divider()
            environmentVariablesList
            addButton
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Text(L10n.t("claude_code_env_vars_title"))
                .font(.headline)

            Spacer()

            Button(L10n.t("reset_to_default")) {
                resetToDefaults()
            }
            .font(.caption)
        }
    }

    private var descriptionView: some View {
        Text(L10n.t("claude_code_env_vars_desc"))
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private var environmentVariablesList: some View {
        VStack(spacing: 8) {
            ForEach($provider.environmentVariables) { $envVar in
                EnvironmentVariableRow(
                    envVar: $envVar,
                    provider: provider,
                    mappings: configManager.mappingsForProvider(provider.id)
                )
            }
        }
    }

    private var addButton: some View {
        Button(L10n.t("add_env_var")) {
            addEnvironmentVariable()
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func resetToDefaults() {
        provider.environmentVariables = ProviderConfig.defaultEnvironmentVariables()
    }

    private func addEnvironmentVariable() {
        let newVar = EnvironmentVariableConfig(
            id: UUID(),
            name: "",
            value: "",
            type: .manual,
            isEnabled: true
        )
        provider.environmentVariables.append(newVar)
    }
}

// MARK: - EnvironmentVariableRow

struct EnvironmentVariableRow: View {
    @Binding var envVar: EnvironmentVariableConfig
    let provider: ProviderConfig
    let mappings: [ModelMapping]

    var body: some View {
        HStack(spacing: 12) {
            enabledToggle
            nameField
            typePicker
            valueEditor
        }
        .padding(.vertical, 4)
        .opacity(envVar.isEnabled ? 1.0 : 0.5)
    }

    // MARK: - Subviews

    private var enabledToggle: some View {
        Toggle("", isOn: $envVar.isEnabled)
            .toggleStyle(.checkbox)
            .labelsHidden()
    }

    private var nameField: some View {
        TextField(L10n.t("env_var_name"), text: $envVar.name)
            .frame(width: 180)
    }

    private var typePicker: some View {
        Picker(L10n.t("env_var_type"), selection: $envVar.type) {
            ForEach(EnvVarType.allCases, id: \.self) { type in
                Text(type.localizedName).tag(type)
            }
        }
        .frame(width: 120)
        .labelsHidden()
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch envVar.type {
        case .manual:
            TextField(L10n.t("env_var_value"), text: $envVar.value)

        case .modelMapping:
            modelMappingPicker

        case .keychainToken:
            keychainIndicator

        case .baseURL:
            baseURLIndicator
        }
    }

    private var modelMappingPicker: some View {
        Picker(L10n.t("select_model"), selection: $envVar.value) {
            Text(L10n.t("auto_select_first")).tag("")
            ForEach(mappings.filter { $0.isEnabled }, id: \.id) { mapping in
                Text("\(mapping.incomingModel) → \(mapping.actualModel)")
                    .tag(mapping.incomingModel)
            }
        }
        .labelsHidden()
    }

    private var keychainIndicator: some View {
        HStack {
            Image(systemName: "key.fill")
                .foregroundColor(.secondary)
            Text(L10n.t("read_from_keychain"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var baseURLIndicator: some View {
        HStack {
            Image(systemName: "link")
                .foregroundColor(.secondary)
            Text(provider.baseURL.absoluteString)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}
