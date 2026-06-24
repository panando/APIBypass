import Foundation
import Hummingbird
import CodexRouterCore

/// Route configuration for Codex Adaptor proxy server.
enum CodexRoutes {
    static func configure(
        router: Router<BasicRequestContext>,
        settingsHandler: @escaping () async -> (Int, String, String)
    ) {
        let requestHandler = CodexRequestHandler()

        router.get("/health") { _, _ in
            return Response(
                status: .ok,
                body: .init(byteBuffer: ByteBuffer(string: #"{"status":"healthy"}"#))
            )
        }

        router.get("/settings/get") { _, _ in
            let (status, contentType, body) = await settingsHandler()
            var headers = HTTPFields()
            headers[.contentType] = contentType
            return Response(
                status: .init(code: status, reasonPhrase: status == 200 ? "OK" : "Error"),
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(string: body))
            )
        }

        router.get("/codex-model-catalog") { _, _ in
            let provider = try? CodexConfigService.shared.getCurrentUpstreamProvider()
            let body = CodexRequestHandler.makeModelCatalogBody(catalog: provider?.modelCatalog)
            var headers = HTTPFields()
            headers[.contentType] = "application/json"
            return Response(
                status: .ok,
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(data: body))
            )
        }

        router.get("/v1/models") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .models)
        }

        router.post("/v1/chat/completions") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .chatCompletions)
        }

        router.post("/v1/responses") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responses)
        }

        router.post("/v1/responses/compact") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responsesCompact)
        }

        // Routes without /v1 prefix (for Codex compatibility)
        router.get("/models") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .models)
        }

        router.post("/chat/completions") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .chatCompletions)
        }

        router.post("/responses") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responses)
        }

        router.post("/responses/compact") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responsesCompact)
        }
    }
}
