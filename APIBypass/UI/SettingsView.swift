import SwiftUI

struct SettingsView: View {
    @ObservedObject var l10n = LocalizationManager.shared

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

            // 关于
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("about"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(L10n.t("about_description"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
        .frame(minWidth: 460, minHeight: 300)
        .frame(width: 500)
    }
}
