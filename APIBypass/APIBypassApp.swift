import SwiftUI

@main
struct APIBypassApp: App {
    @StateObject private var configManager = ConfigManager()
    @State private var server: HTTPServer?
    @State private var isRunning = false
    @State private var didAutoStart = false

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
                port: server?.port ?? (UserDefaults.standard.integer(forKey: "serverPort") > 0 ? UserDefaults.standard.integer(forKey: "serverPort") : 8390),
                onStart: startServer,
                onStop: stopServer
            )
        } label: {
            labelView
        }
        .menuBarExtraStyle(.menu)
    }

    private var labelView: some View {
        Group {
            if let icon = menuBarIcon(running: isRunning) {
                Image(nsImage: icon)
            } else {
                Image(systemName: isRunning ? "network" : "network.slash")
            }
        }
        .onAppear {
            NSApplication.shared.setActivationPolicy(.regular)
            if !didAutoStart {
                didAutoStart = true
                startServer()
            }
        }
    }

    private func startServer() {
        print("[APIBypass] startServer() called")
        Task {
            let newServer = HTTPServer(configManager: configManager)
            do {
                print("[APIBypass] calling newServer.start()...")
                try await newServer.start()
                server = newServer
                isRunning = true
                print("[APIBypass] server started, isRunning=true")
            } catch {
                print("[APIBypass] Failed to start server: \(error)")
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
