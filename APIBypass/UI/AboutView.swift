import SwiftUI

struct AboutView: View {
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "APIBypass"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? "Version \(version)" : "Version \(version) (\(build))"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text(appName)
                .font(.title.bold())

            Text(versionText)
                .font(.callout)
                .foregroundColor(.secondary)

            Text(copyright)
                .font(.callout)
                .foregroundColor(.secondary)

            if let url = URL(string: "https://github.com/panando/APIBypass") {
                Link("https://github.com/panando/APIBypass", destination: url)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .padding(32)
        .frame(minWidth: 320, minHeight: 260)
    }
}

#Preview {
    AboutView()
}
