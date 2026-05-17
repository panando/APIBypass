import SwiftUI

struct MenuBarView: View {
    var body: some View {
        VStack {
            Text("APIBypass")
                .font(.headline)
            Divider()
            Button("打开配置...") {
                // TODO: 打开配置窗口
            }
            Divider()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
