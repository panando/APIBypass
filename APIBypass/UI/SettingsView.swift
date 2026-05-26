import SwiftUI

struct SettingsView: View {
    @ObservedObject var l10n = LocalizationManager.shared
    @AppStorage("serverPort") private var serverPort: Int = 8390

    private var portString: Binding<String> {
        Binding<String>(
            get: { String(serverPort) },
            set: { if let v = Int($0) { serverPort = v } }
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            // 语言
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("language"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("", selection: $l10n.currentLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Text(L10n.t("language_hint"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // 服务端口
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("server_port"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    TextField("", text: portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("127.0.0.1:\(String(serverPort))")
                        .font(.callout.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Text(L10n.t("port_hint"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // 关于
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("about"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(L10n.t("about_description"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("\(L10n.t("version")): 0.3.2")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .foregroundColor(.secondary)
                    Text(L10n.t("github_repo"))
                        .font(.callout)
                        .foregroundColor(.accentColor)
                }
                .onTapGesture {
                    if let url = URL(string: "https://github.com/panando/APIBypass") {
                        NSWorkspace.shared.open(url)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                    Text(L10n.t("license"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Spacer()
        }
        .padding()
        .frame(minWidth: 460, idealWidth: 500, minHeight: 300)
    }
}
