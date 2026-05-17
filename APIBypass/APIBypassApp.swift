import SwiftUI

@main
struct APIBypassApp: App {
    @StateObject private var configManager = ConfigManager()
    @State private var server = HTTPServer(configManager: ConfigManager())

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        let srv = HTTPServer(configManager: configManager)
        _server = State(initialValue: srv)
        Task {
            try? await srv.start()
        }
    }

    private var menuBarImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                configManager: configManager,
                server: server
            )
        } label: {
            if let icon = menuBarImage {
                Image(nsImage: icon)
            } else if server.isRunning {
                Image(systemName: "network")
            } else {
                Image(systemName: "network.slash")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
