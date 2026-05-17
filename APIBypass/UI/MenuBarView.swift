import SwiftUI

struct MenuBarView: View {
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
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
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
}
