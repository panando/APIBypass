import SwiftUI

struct MenuBarView: View {
    var body: some View {
        VStack {
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("服务运行中")
            }
            Text("端口: 8390")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            Button("打开配置...") {
                openConfigWindow()
            }

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func openConfigWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "APIBypass 配置"
        window.contentView = NSHostingView(rootView: ConfigWindow())
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
