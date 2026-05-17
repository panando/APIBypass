import SwiftUI

@main
struct APIBypassApp: App {
    var body: some Scene {
        MenuBarExtra("APIBypass", systemImage: "network") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
