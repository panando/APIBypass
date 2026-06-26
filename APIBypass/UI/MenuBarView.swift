import SwiftUI

struct MenuBarView: View {
    let configManager: ConfigManager
    let codexAdaptor: CodexAdaptorService
    @Binding var isRunning: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onStartCodex: () -> Void
    let onStopCodex: () -> Void

    @ObservedObject private var l10n = LocalizationManager.shared
    @AppStorage("bypassMode") var bypassMode: Bool = false

    private var isCodexRunning: Bool {
        switch codexAdaptor.cdpConnectionState {
        case .connected, .injected: return true
        default: return false
        }
    }

    var body: some View {
        VStack {
            // APIBypass服务 - toggle with status indicator
            Button {
                if isRunning { onStop() } else { onStart() }
            } label: {
                HStack {
                    Text(L10n.t("apibypass_service"))
                    Spacer()
                    Circle()
                        .fill(isRunning ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                }
            }

            // Codex适配服务 - toggle with status indicator
            Button {
                if codexAdaptor.isRunning { onStopCodex() } else { onStartCodex() }
            } label: {
                HStack {
                    Text(L10n.t("codex_adaptor_service"))
                    Spacer()
                    Circle()
                        .fill(codexAdaptor.isRunning ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                }
            }

            Divider()

            // 启动Codex - disabled when already running
            Button(L10n.t("launch_codex")) {
                launchCodex()
            }
            .disabled(isCodexRunning)

            Button(L10n.t("launch_claude_code")) {
                openLaunchClaudeCodeWindow()
            }
            .disabled(configManager.providers.isEmpty)

            // 纯代理模式 - toggle with status indicator
            Button {
                bypassMode.toggle()
            } label: {
                HStack {
                    Text(L10n.t("bypass_mode"))
                    Spacer()
                    Circle()
                        .fill(bypassMode ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                }
            }

            Divider()

            Button(L10n.t("configure_apibypass")) {
                openConfigWindow()
            }

            Button(L10n.t("configure_codex_adaptor")) {
                openCodexAdaptorWindow()
            }

            Button(L10n.t("settings")) {
                openSettingsWindow()
            }

            Button(L10n.t("help")) {
                openHelpWindow()
            }

            Button(L10n.t("about")) {
                openAboutWindow()
            }

            Divider()

            Button(L10n.t("quit")) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func launchCodex() {
        Task {
            // Start adaptor service if not running
            if !codexAdaptor.isRunning {
                try? await codexAdaptor.start()
            }
        }
    }

    private func openConfigWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: { $0.title == "APIBypass" || $0.identifier?.rawValue == "config-window" }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "APIBypass"
        window.identifier = NSUserInterfaceItemIdentifier("config-window")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ConfigWindow(configManager: configManager))
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.becomeKey()
    }

    private func openSettingsWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "settings-window" }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView())
        hostingView.sizingOptions = [.minSize, .intrinsicContentSize]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("settings_title")
        window.identifier = NSUserInterfaceItemIdentifier("settings-window")
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.becomeKey()
    }

    private func openLaunchClaudeCodeWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == "launch-claude-window"
        }) {
            existingWindow.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .launchClaudeCodeWindowDidShow, object: nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("launch_claude_code")
        window.identifier = NSUserInterfaceItemIdentifier("launch-claude-window")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LaunchClaudeCodeView(configManager: configManager))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func openCodexAdaptorWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == "codex-adaptor-window"
        }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        // Pre-load config to populate cache before view appears
        Task {
            _ = await CodexAdaptorConfigStore.shared.load()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("codex_adaptor")
        window.identifier = NSUserInterfaceItemIdentifier("codex-adaptor-window")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CodexAdaptorView(
            configManager: configManager,
            codexAdaptor: codexAdaptor
        ))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func openHelpWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == "help-window"
        }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("help_window_title")
        window.identifier = NSUserInterfaceItemIdentifier("help-window")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HelpView())
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func openAboutWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == "about-window"
        }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hostingView = NSHostingView(rootView: AboutView())
        hostingView.sizingOptions = [.minSize, .intrinsicContentSize]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("about")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.identifier = NSUserInterfaceItemIdentifier("about-window")
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}