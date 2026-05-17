import SwiftUI

struct MenuBarView: View {
    let configManager: ConfigManager
    @ObservedObject var server: HTTPServer

    var body: some View {
        VStack {
            HStack {
                Circle()
                    .fill(server.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(server.isRunning ? "服务运行中" : "服务已停止")
            }

            if server.isRunning {
                Text("端口: \(server.port)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button("打开配置...") {
                openConfigWindow()
            }

            if server.isRunning {
                Button("停止服务") {
                    stopServer()
                }
            } else {
                Button("启动服务") {
                    startServer()
                }
            }

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func startServer() {
        Task {
            let newServer = HTTPServer(configManager: configManager)
            do {
                try await newServer.start()
                // server reference is managed by parent via @ObservedObject
            } catch {
                print("Failed to start server: \(error)")
            }
        }
    }

    private func stopServer() {
        Task {
            await server.stop()
        }
    }

    private func openConfigWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: { $0.title == "APIBypass 配置" || $0.identifier?.rawValue == "config-window" }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "APIBypass 配置"
        window.identifier = NSUserInterfaceItemIdentifier("config-window")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ConfigWindow(configManager: configManager))
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.becomeKey()
    }
}
