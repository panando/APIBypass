import SwiftUI

struct SettingsView: View {
    private let l10n = LocalizationManager.shared
    @AppStorage("serverPort") private var serverPort: Int = 8390
    @AppStorage("traceLogEnabled") private var traceLogEnabled: Bool = false

    private var portString: Binding<String> {
        Binding<String>(
            get: { String(serverPort) },
            set: { if let v = Int($0) { serverPort = v } }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding<AppLanguage>(
            get: { l10n.currentLanguage },
            set: { l10n.currentLanguage = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            // 语言
            HStack(spacing: 0) {
                Text(L10n.t("language"))
                    .font(.headline)
                Picker("", selection: languageBinding) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                Spacer(minLength: 0)
            }
            .cardStyle()

            // 服务端口
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("server_port"))
                    .font(.headline)

                HStack(spacing: 12) {
                    TextField("", text: portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("127.0.0.1:\(String(serverPort))")
                        .font(.callout.monospacedDigit())
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }

                Text(L10n.t("port_hint"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardStyle()

            // 追踪日志
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(L10n.t("trace_log"))
                        .font(.headline)
                    Toggle("", isOn: $traceLogEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Spacer(minLength: 0)
                }

                Text(L10n.t("trace_log_desc"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if traceLogEnabled {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(L10n.t("trace_log_path")):")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Text(TraceLogger.traceDirectory.path)
                            .font(.callout.monospaced())
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .cardStyle()
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 280, alignment: .top)
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
    }
}
