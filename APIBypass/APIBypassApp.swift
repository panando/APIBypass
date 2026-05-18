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

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                configManager: configManager,
                isRunning: $isRunning,
                onStart: startServer,
                onStop: stopServer
            )
        } label: {
            if let nsImage = NSImage(contentsOf: Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ?? URL(fileURLWithPath: "")) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(isRunning ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                    }
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
