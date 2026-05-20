import SwiftUI

struct MenuBarView: View {
    let configManager: ConfigManager
    @Binding var isRunning: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some View {
        VStack {
            HStack {
                Circle()
                    .fill(isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(isRunning ? L10n.t("server_running") : L10n.t("server_stopped"))
            }

            if isRunning {
                Text("端口: 8390")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button(L10n.t("configure")) {
                openConfigWindow()
            }

            Button(L10n.t("settings")) {
                openSettingsWindow()
            }

            Button(isRunning ? L10n.t("stop_server") : L10n.t("start_server")) {
                if isRunning {
                    onStop()
                } else {
                    onStart()
                }
            }

            Divider()

            Button(L10n.t("quit")) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func openConfigWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: { $0.title == "APIBypass" || $0.identifier?.rawValue == "config-window" }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "APIBypass"
        window.identifier = NSUserInterfaceItemIdentifier("config-window")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ConfigWindow(configManager: configManager))
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.becomeKey()
    }

    private func openSettingsWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "settings-window" }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("settings_title")
        window.identifier = NSUserInterfaceItemIdentifier("settings-window")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.becomeKey()
    }
}
