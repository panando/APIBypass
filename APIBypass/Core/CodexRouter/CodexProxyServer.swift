import Foundation
import Hummingbird
import CodexRouterCore

/// HTTP proxy server for Codex Adaptor.
final class CodexProxyServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var port: Int = 15721

    private var app: Application<RouterResponder<BasicRequestContext>>?

    init() {}

    func start(
        port: Int = 15721,
        settingsHandler: @escaping () async -> (Int, String, String)
    ) async throws {
        self.port = port

        let router = Router()
        CodexRoutes.configure(router: router, settingsHandler: settingsHandler)

        let responder = router.buildResponder()
        let app = Application(
            responder: responder,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )

        self.app = app

        Task {
            do {
                try await app.run()
            } catch {
                print("[CodexAdaptor] Server error: \(error)")
            }
        }

        await MainActor.run {
            self.isRunning = true
        }

        CodexLogStore.shared.info("[CodexAdaptor] Server started on port \(port)")
    }

    func stop() async {
        self.app = nil

        await MainActor.run {
            self.isRunning = false
        }

        CodexLogStore.shared.info("[CodexAdaptor] Server stopped")
    }
}
