import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import ServiceLifecycle

final class HTTPServer: @unchecked Sendable {
    private let configManager: ConfigManager
    private let keychain: KeychainService
    private let proxyEngine: ProxyEngine
    private let networkService: NetworkService
    private var serviceGroup: ServiceGroup?

    let port: Int = 8390

    init(configManager: ConfigManager, keychain: KeychainService = KeychainService()) {
        self.configManager = configManager
        self.keychain = keychain
        self.proxyEngine = ProxyEngine()
        self.networkService = NetworkService()
    }

    func start() async throws {
        let router = Router()

        // OpenAI 兼容端点
        router.post("/v1/chat/completions") { request, context in
            return try await self.handleProxyRequest(request, context, format: .openai)
        }

        // Anthropic 端点
        router.post("/v1/messages") { request, context in
            return try await self.handleProxyRequest(request, context, format: .anthropic)
        }

        // 模型列表端点
        router.get("/v1/models") { request, context in
            let models = self.configManager.mappings.map { mapping in
                ["id": mapping.incomingModel, "object": "model"]
            }
            let response: [String: Any] = ["object": "list", "data": models]
            let data = try JSONSerialization.data(withJSONObject: response)
            return Response(
                status: .ok,
                body: .init(byteBuffer: ByteBuffer(data: data))
            )
        }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )

        let group = ServiceGroup(
            configuration: .init(services: [app], logger: app.logger)
        )
        self.serviceGroup = group
        try await group.run()
    }

    func stop() async {
        await serviceGroup?.triggerGracefulShutdown()
        serviceGroup = nil
    }

    private func handleProxyRequest(
        _ request: Request,
        _ context: BasicRequestContext,
        format: APIFormat
    ) async throws -> Response {
        // 读取请求体
        let body = try await request.body.collect(upTo: 10 * 1024 * 1024) // 10MB limit
        let data = Data(body.readableBytesView)

        // 解析模型名称
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? String,
              let mapping = configManager.findMapping(for: model) else {
            let errorData = #"{"error": "Model not found or no mapping configured"}"#.data(using: .utf8)!
            return Response(
                status: .badRequest,
                body: .init(byteBuffer: ByteBuffer(data: errorData))
            )
        }

        // 转换请求
        let transformedData: Data
        do {
            transformedData = try proxyEngine.transformRequest(data: data, mapping: mapping, format: format)
        } catch {
            let errorData = #"{"error": "Request transformation failed"}"#.data(using: .utf8)!
            return Response(
                status: .internalServerError,
                body: .init(byteBuffer: ByteBuffer(data: errorData))
            )
        }

        // 获取 API Key
        let apiKey: String
        do {
            apiKey = try keychain.retrieve(forKey: mapping.id.uuidString)
        } catch {
            let errorData = #"{"error": "API key not configured"}"#.data(using: .utf8)!
            return Response(
                status: .internalServerError,
                body: .init(byteBuffer: ByteBuffer(data: errorData))
            )
        }

        // 构建上游请求
        let endpoint = format == .openai ? "/v1/chat/completions" : "/v1/messages"
        let upstreamURL = mapping.baseURL.appendingPathComponent(endpoint)

        let upstreamRequest = networkService.buildRequest(
            url: upstreamURL,
            method: "POST",
            body: transformedData,
            apiKey: apiKey,
            provider: mapping.apiProvider,
            customHeaders: mapping.parameters.customHeaders
        )

        // 发送请求并返回响应
        do {
            let (responseData, response) = try await networkService.send(request: upstreamRequest)
            let httpResponse = response as! HTTPURLResponse

            var headers = HTTPFields()
            for (key, value) in httpResponse.allHeaderFields {
                if let name = HTTPField.Name(String(describing: key)) {
                    headers[name] = String(describing: value)
                }
            }

            return Response(
                status: HTTPResponse.Status(code: httpResponse.statusCode),
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(data: responseData))
            )
        } catch {
            let errorData = #"{"error": "Upstream API request failed"}"#.data(using: .utf8)!
            return Response(
                status: .badGateway,
                body: .init(byteBuffer: ByteBuffer(data: errorData))
            )
        }
    }
}
