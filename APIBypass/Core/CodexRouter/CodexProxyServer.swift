import Foundation
import Hummingbird
import CodexRouterCore

/// HTTP proxy server for Codex Adaptor.
final class CodexProxyServer {
    private var app: Application<RouterResponder<BasicRequestContext>>?
    private var runTask: Task<Void, Never>?

    init() {}

    func start(
        port: Int = 15721,
        settingsHandler: @escaping () async -> (Int, String, String)
    ) async throws {
        let router = Router()
        CodexRoutes.configure(router: router, settingsHandler: settingsHandler)

        let responder = router.buildResponder()
        let app = Application(
            responder: responder,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )

        self.app = app

        let task = Task {
            do {
                try await app.run()
            } catch {
                print("[CodexAdaptor] Server error: \(error)")
            }
        }
        runTask = task

        CodexLogStore.shared.info("[CodexAdaptor] Server started on port \(port)")
    }

    func stop() async {
        runTask?.cancel()
        runTask = nil
        app = nil

        CodexLogStore.shared.info("[CodexAdaptor] Server stopped")
    }
}
