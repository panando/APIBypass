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

    private func menuBarIcon(running: Bool) -> NSImage? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let baseImage = NSImage(contentsOf: url) else { return nil }

        let size = NSSize(width: 18, height: 18)
        let dotSize: CGFloat = 5
        let dotColor = running ? NSColor.systemGreen : NSColor.systemGray

        let composited = NSImage(size: size)
        composited.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: size),
                       from: .zero, operation: .copy, fraction: 1.0)

        let dotRect = NSRect(x: size.width - dotSize - 1,
                             y: 1,
                             width: dotSize,
                             height: dotSize)
        let path = NSBezierPath(ovalIn: dotRect)
        dotColor.setFill()
        path.fill()
        composited.unlockFocus()
        composited.isTemplate = false
        return composited
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
            if let icon = menuBarIcon(running: isRunning) {
                Image(nsImage: icon)
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
