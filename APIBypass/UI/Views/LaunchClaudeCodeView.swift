import SwiftUI

struct LaunchClaudeCodeView: View {
    @ObservedObject var configManager: ConfigManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProviderId: UUID?
    @State private var isLaunching = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            headerView

            providerPicker

            if let providerId = selectedProviderId,
               let provider = configManager.findProvider(for: providerId) {
                environmentVariablesPreview(provider: provider)
            }

            if let error = errorMessage {
                errorView(message: error)
            }

            Spacer()

            buttonBar
        }
        .padding()
        .frame(width: 480, height: 500)
    }

    private var headerView: some View {
        HStack {
            Image(systemName: "terminal.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("启动 Claude Code")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
        }
    }

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择提供商")
                .font(.headline)

            Picker("提供商", selection: $selectedProviderId) {
                Text("请选择").tag(UUID?.none)
                ForEach(configManager.providers) { provider in
                    Text(provider.name).tag(provider.id as UUID?)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func environmentVariablesPreview(provider: ProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("环境变量预览")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(provider.environmentVariables.filter { $0.isEnabled }) { envVar in
                        HStack {
                            Text("\(envVar.name)=")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(previewValue(for: envVar, provider: provider))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }

    private func errorView(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var buttonBar: some View {
        HStack {
            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.escape)

            Spacer()

            Button("启动") {
                launchClaudeCode()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .disabled(selectedProviderId == nil || isLaunching)
        }
    }

    private func previewValue(for envVar: EnvironmentVariableConfig, provider: ProviderConfig) -> String {
        switch envVar.type {
        case .manual:
            return envVar.value.isEmpty ? "(empty)" : envVar.value
        case .baseURL:
            return provider.baseURL.absoluteString
        case .modelMapping:
            return "(from mapping)"
        case .keychainToken:
            return "(from Keychain)"
        }
    }

    private func launchClaudeCode() {
        guard let providerId = selectedProviderId,
              let provider = configManager.findProvider(for: providerId) else {
            errorMessage = "未选择提供商"
            return
        }

        isLaunching = true
        errorMessage = nil

        let launcher = ClaudeCodeLauncher()
        let configuration = LaunchConfiguration(
            provider: provider,
            selectedMapping: nil,
            customEnvVars: [:]
        )

        do {
            let process = try launcher.launchClaudeCode(configuration: configuration)

            process.terminationHandler = { [weak self] process in
                DispatchQueue.main.async {
                    self?.isLaunching = false
                    if process.terminationStatus != 0 {
                        self?.errorMessage = "Claude Code 已退出，退出码: \(process.terminationStatus)"
                    } else {
                        self?.dismiss()
                    }
                }
            }

            dismiss()

        } catch {
            isLaunching = false
            errorMessage = error.localizedDescription
        }
    }
}
