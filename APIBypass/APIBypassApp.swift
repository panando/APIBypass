import SwiftUI

@main
struct APIBypassApp: App {
    @StateObject private var configManager = ConfigManager()
    @StateObject private var codexAdaptor = CodexAdaptorService()
    @State private var server: HTTPServer?
    @State private var isRunning = false
    @State private var didAutoStart = false
    @State private var isTransitioning = false

    private func menuBarIcon(running: Bool, codexRunning: Bool) -> NSImage? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let baseImage = NSImage(contentsOf: url) else { return nil }

        let size = NSSize(width: 18, height: 18)
        let dotSize: CGFloat = 5

        let composited = NSImage(size: size)
        composited.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: size),
                       from: .zero, operation: .copy, fraction: 1.0)

        // Top-left dot: Codex Adaptor status
        let leftDotColor = codexRunning ? NSColor.systemGreen : NSColor.systemGray
        let leftDotRect = NSRect(x: 1, y: size.height - dotSize - 1, width: dotSize, height: dotSize)
        let leftPath = NSBezierPath(ovalIn: leftDotRect)
        leftDotColor.setFill()
        leftPath.fill()

        // Top-right dot: APIBypass server status
        let rightDotColor = running ? NSColor.systemGreen : NSColor.systemGray
        let rightDotRect = NSRect(x: size.width - dotSize - 1,
                                  y: size.height - dotSize - 1,
                                  width: dotSize,
                                  height: dotSize)
        let rightPath = NSBezierPath(ovalIn: rightDotRect)
        rightDotColor.setFill()
        rightPath.fill()

        composited.unlockFocus()
        composited.isTemplate = false
        return composited
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                configManager: configManager,
                codexAdaptor: codexAdaptor,
                isRunning: $isRunning,
                onStart: startServer,
                onStop: stopServer,
                onStartCodex: startCodexAdaptor,
                onStopCodex: stopCodexAdaptor
            )
        } label: {
            labelView
        }
        .menuBarExtraStyle(.menu)
    }

    private var labelView: some View {
        Group {
            if let icon = menuBarIcon(running: isRunning, codexRunning: codexAdaptor.isRunning) {
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
        guard !isTransitioning, server == nil else { return }
        isTransitioning = true
        print("[APIBypass] startServer() called")
        Task {
            let newServer = HTTPServer()
            do {
                print("[APIBypass] calling newServer.start()...")
                try await newServer.start()
                server = newServer
                isRunning = true
                print("[APIBypass] server started, isRunning=true")
            } catch {
                print("[APIBypass] Failed to start server: \(error)")
            }
            isTransitioning = false
        }
    }

    private func stopServer() {
        guard !isTransitioning, server != nil else { return }
        isTransitioning = true
        Task {
            await server?.stop()
            server = nil
            isRunning = false
            isTransitioning = false
        }
    }

    private func startCodexAdaptor() {
        Task {
            do {
                try await codexAdaptor.start()
            } catch {
                print("[APIBypass] Failed to start Codex Adaptor: \(error)")
            }
        }
    }

    private func stopCodexAdaptor() {
        Task {
            await codexAdaptor.stop()
        }
    }
}
