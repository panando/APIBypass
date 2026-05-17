import SwiftUI

@main
struct APIBypassApp: App {
    @StateObject private var configManager = ConfigManager()
    @State private var server: HTTPServer?
    @State private var isRunning = false

    init() {
        // 设置应用为常规应用，这样窗口可以正常显示和接收输入
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
                await MainActor.run {
                    server = newServer
                    isRunning = true
                }
            } catch {
                print("Failed to start server: \(error)")
            }
        }
    }

    private func stopServer() {
        Task {
            await server?.stop()
            await MainActor.run {
                server = nil
                isRunning = false
            }
        }
    }
}
