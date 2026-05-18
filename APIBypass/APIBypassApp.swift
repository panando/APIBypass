import SwiftUI

@main
struct APIBypassApp: App {
    @StateObject private var configManager = ConfigManager()
    @State private var server: HTTPServer?
    @State private var isRunning = false
    @State private var errorMessage: String?

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
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
                isRunning: $isRunning,
                onStart: startServer,
                onStop: stopServer
            )
        } label: {
            if let icon = menuBarImage {
                Image(nsImage: icon)
                    .renderingMode(.template)
                    .foregroundColor(isRunning ? .green : .gray)
            } else {
                Image(systemName: isRunning ? "network" : "network.slash")
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private func startServer() {
        Task {
            let newServer = HTTPServer(configManager: configManager)
            do {
                try await newServer.start()
                server = newServer
                isRunning = true
            } catch {
                print("Failed to start server: \(error)")
            }
        }
    }

    private func stopServer() {
        Task {
            await server?.stop()
            server = nil
            isRunning = false
        }
    }
}
