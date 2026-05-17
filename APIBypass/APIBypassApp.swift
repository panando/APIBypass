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
        MenuBarExtra("APIBypass", systemImage: isRunning ? "network" : "network.slash") {
            MenuBarView(
                isRunning: $isRunning,
                onStart: startServer,
                onStop: stopServer
            )
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
