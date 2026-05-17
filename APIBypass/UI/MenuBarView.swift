import SwiftUI

struct MenuBarView: View {
    let configManager: ConfigManager
    @Binding var isRunning: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack {
            HStack {
                Circle()
                    .fill(isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(isRunning ? "服务运行中" : "服务已停止")
            }

            if isRunning {
                Text("端口: 8390")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button("打开配置...") {
                openConfigWindow()
            }

            Button(isRunning ? "停止服务" : "启动服务") {
                if isRunning {
                    onStop()
                } else {
                    onStart()
                }
            }

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func openConfigWindow() {
        // 先激活应用
        NSApplication.shared.activate(ignoringOtherApps: true)

        // 查找或创建配置窗口
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
