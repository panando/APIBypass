import SwiftUI

/// Provider 详情页的环境变量配置卡片
struct EnvironmentVariablesCard: View {
    @Binding var environmentVariables: [EnvironmentVariableConfig]
    let providerId: UUID
    let baseURL: URL
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
            ForEach($environmentVariables) { $envVar in
                EnvironmentVariableRow(
                    envVar: $envVar,
                    baseURL: baseURL,
                    mappings: configManager.mappingsForProvider(providerId)
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
        environmentVariables = ProviderConfig.defaultEnvironmentVariables()
    }

    private func addEnvironmentVariable() {
        let newVar = EnvironmentVariableConfig(
            id: UUID(),
            name: "",
            value: "",
            type: .manual,
            isEnabled: true
        )
        environmentVariables.append(newVar)
    }
}

// MARK: - EnvironmentVariableRow

struct EnvironmentVariableRow: View {
    @Binding var envVar: EnvironmentVariableConfig
    let baseURL: URL
    let mappings: [ModelMapping]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 第一行：启用开关 + 变量名
            HStack(spacing: 8) {
                Toggle("", isOn: $envVar.isEnabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                TextField(L10n.t("env_var_name"), text: $envVar.name)
                    .textFieldStyle(.roundedBorder)
            }

            // 第二行：类型选择器 + 值编辑器
            HStack(spacing: 8) {
                Picker("", selection: $envVar.type) {
                    ForEach(EnvironmentVariableConfig.EnvVarType.allCases, id: \.self) { type in
                        Text(typeDisplayName(type)).tag(type)
                    }
                }
                .frame(width: 140)
                .labelsHidden()

                valueEditor
            }
            .padding(.leading, 24)
        }
        .padding(.vertical, 6)
        .opacity(envVar.isEnabled ? 1.0 : 0.5)
    }

    // MARK: - Subviews

    private func typeDisplayName(_ type: EnvironmentVariableConfig.EnvVarType) -> String {
        switch type {
        case .manual: return L10n.t("envvar_manual")
        case .modelMapping: return L10n.t("envvar_model_mapping")
        case .keychainToken: return L10n.t("envvar_keychain_token")
        case .baseURL: return L10n.t("envvar_base_url")
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch envVar.type {
        case .manual:
            TextField(L10n.t("env_var_value"), text: $envVar.value)
                .textFieldStyle(.roundedBorder)

        case .modelMapping:
            modelMappingPicker

        case .keychainToken:
            keychainIndicator

        case .baseURL:
            baseURLIndicator
        }
    }

    private var modelMappingPicker: some View {
        Picker("", selection: $envVar.value) {
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
            Text(baseURL.absoluteString)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}
