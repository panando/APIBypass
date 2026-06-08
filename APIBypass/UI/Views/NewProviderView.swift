import SwiftUI

struct NewProviderView: View {
    let configManager: ConfigManager
    let keychain: KeychainService
    var onCreated: ((ProviderConfig) -> Void)? = nil

    @Environment(\.dismiss) var dismiss
    private let l10n = LocalizationManager.shared

    @State private var name = ""
    @State private var apiProvider: APIProvider = .openai
    @State private var baseURL = ""
    @State private var apiKey = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.t("new_provider"))
                .font(.headline)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("provider_info"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    HStack {
                        Text(L10n.t("provider_name"))
                            .frame(width: 100, alignment: .trailing)
                        TextField(L10n.t("provider_name_placeholder"), text: $name)
                    }
                    HStack {
                        Text(L10n.t("api_provider"))
                            .frame(width: 100, alignment: .trailing)
                        Picker("", selection: $apiProvider) {
                            Text(L10n.t("provider_type_openai")).tag(APIProvider.openai)
                            Text(L10n.t("provider_type_openai_responses")).tag(APIProvider.openaiResponses)
                            Text(L10n.t("provider_type_anthropic")).tag(APIProvider.anthropic)
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(x: -8)
                        .onChange(of: apiProvider) { _, newValue in
                            baseURL = newValue.defaultBaseURL.absoluteString
                        }
                    }
                    HStack {
                        Text(L10n.t("base_url"))
                            .frame(width: 100, alignment: .trailing)
                        TextField(L10n.t("base_url_placeholder"), text: $baseURL)
                    }
                    HStack {
                        Text(L10n.t("api_key"))
                            .frame(width: 100, alignment: .trailing)
                        SecureField(L10n.t("api_key_placeholder"), text: $apiKey)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            HStack {
                Button(L10n.t("cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.t("create")) {
                    createProvider()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || apiKey.isEmpty)
            }
            .padding(.bottom, 8)
        }
        .padding()
        .frame(width: 450, height: 320)
        .onAppear {
            if name.isEmpty {
                name = apiProvider == .openai ? "OpenAI" : "Anthropic"
            }
            baseURL = apiProvider.defaultBaseURL.absoluteString
        }
    }

    private func createProvider() {
        let provider = ProviderConfig(
            name: name,
            apiProvider: apiProvider,
            baseURL: URL(string: baseURL) ?? apiProvider.defaultBaseURL,
            environmentVariables: ProviderConfig.defaultEnvironmentVariables()
        )

        configManager.addProvider(provider)
        Task {
            try? await keychain.save(apiKey, forKey: provider.id.uuidString)
        }
        onCreated?(provider)
        dismiss()
    }
}
