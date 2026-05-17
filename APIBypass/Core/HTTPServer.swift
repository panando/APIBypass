import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import ServiceLifecycle

@MainActor
final class HTTPServer: ObservableObject {
    private let configManager: ConfigManager
    private let keychain: KeychainService
    private let proxyEngine: ProxyEngine
    private let networkService: NetworkService
    private var app: Application<RouterResponder<BasicRequestContext>>?
    private var serviceGroup: ServiceGroup?
    private var serverTask: Task<Void, Never>?

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
        router.post("/v1/chat/completions") { [weak self] request, context in
            guard let self = self else {
                return Response(status: .internalServerError, body: .init(byteBuffer: ByteBuffer()))
            }
            return try await self.handleProxyRequest(request, context, format: .openai)
        }

        // Anthropic 端点
        router.post("/v1/messages") { [weak self] request, context in
            guard let self = self else {
                return Response(status: .internalServerError, body: .init(byteBuffer: ByteBuffer()))
            }
            return try await self.handleProxyRequest(request, context, format: .anthropic)
        }

        // 模型列表端点
        router.get("/v1/models") { request, context in
            let models = await self.configManager.mappings.map { mapping in
                ["id": mapping.incomingModel, "object": "model"]
            }
            let response: [String: Any] = ["object": "list", "data": models]
            let data = try JSONSerialization.data(withJSONObject: response)
            return Response(
                status: .ok,
                body: .init(byteBuffer: ByteBuffer(data: data))
            )
        }

        let newApp = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )

        self.app = newApp

        // 在后台启动服务，保存 Task 引用防止被取消
        serverTask = Task { @MainActor in
            do {
                let group = ServiceGroup(
                    configuration: .init(services: [newApp], logger: newApp.logger)
                )
                self.serviceGroup = group
                try await group.run()
            } catch {
                print("[APIBypass] Server error: \(error)")
            }
        }
    }

    func stop() async {
        await serviceGroup?.triggerGracefulShutdown()
        serverTask?.cancel()
        serverTask = nil
        serviceGroup = nil
        app = nil
    }

    private func handleProxyRequest(
        _ request: Request,
        _ context: BasicRequestContext,
        format: APIFormat
    ) async throws -> Response {
        // 读取请求体
        let body = try await request.body.collect(upTo: 10 * 1024 * 1024)
        let data = Data(body.readableBytesView)

        // 日志: 原始请求
        if let incomingBody = String(data: data, encoding: .utf8) {
            print("[APIBypass] === 收到请求 (format: \(format)) ===")
            print("[APIBypass] 原始请求体: \(incomingBody)")
        }

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

        // 构建上游请求 URL
        let upstreamURL: URL
        let baseURLString = mapping.baseURL.absoluteString

        // 智能处理 URL：如果 baseURL 已包含 /v1，不再重复添加
        if baseURLString.hasSuffix("/v1") || baseURLString.hasSuffix("/v1/") {
            // baseURL 已包含 /v1，直接拼接端点
            let endpointPath = format == .openai ? "chat/completions" : "messages"
            upstreamURL = mapping.baseURL.appendingPathComponent(endpointPath)
        } else {
            // baseURL 不包含 /v1，添加完整端点
            let endpoint = format == .openai ? "/v1/chat/completions" : "/v1/messages"
            upstreamURL = mapping.baseURL.appendingPathComponent(endpoint)
        }

        let upstreamRequest = networkService.buildRequest(
            url: upstreamURL,
            method: "POST",
            body: transformedData,
            apiKey: apiKey,
            provider: mapping.apiProvider,
            customHeaders: mapping.parameters.customHeaders
        )

        // 日志: 转换后请求
        if let transformedBody = String(data: transformedData, encoding: .utf8) {
            print("[APIBypass] 转换后请求体: \(transformedBody)")
            print("[APIBypass] 上游 URL: \(upstreamURL.absoluteString)")
            print("[APIBypass] 实际模型: \(mapping.actualModel)")
        }

        // 发送请求并返回响应
        do {
            let (responseData, response) = try await networkService.send(request: upstreamRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[APIBypass] 上游响应不是 HTTPURLResponse, 直接透传")
                return Response(
                    status: .ok,
                    body: .init(byteBuffer: ByteBuffer(data: responseData))
                )
            }

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
            print("[APIBypass] 上游请求失败: \(error)")
            let errorData = #"{"error": "Upstream API request failed"}"#.data(using: .utf8)!
            return Response(
                status: .badGateway,
                body: .init(byteBuffer: ByteBuffer(data: errorData))
            )
        }
    }
}
