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

        // 在后台启动服务
        Task { @MainActor in
            do {
                let group = ServiceGroup(
                    configuration: .init(services: [newApp], logger: newApp.logger)
                )
                self.serviceGroup = group
                try await group.run()
            } catch {
                print("Server error: \(error)")
            }
        }
    }

    func stop() async {
        await serviceGroup?.triggerGracefulShutdown()
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
        print("\n")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📥 收到客户端请求 [\(format == .openai ? "OpenAI" : "Anthropic") 格式]")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        if let incomingBody = String(data: data, encoding: .utf8) {
            print("请求体 (原始):")
            print(prettyJSON(incomingBody) ?? incomingBody)
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

        // 检测是否为流式请求
        let isStreaming = (json["stream"] as? Bool) ?? false

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
        print("\n📤 转发到上游 API\(isStreaming ? " [流式模式]" : "")")
        print("────────────────────────────────────────────────────────────")
        print("上游 URL: \(upstreamURL.absoluteString)")
        print("实际模型: \(mapping.actualModel)")
        if let transformedBody = String(data: transformedData, encoding: .utf8) {
            print("请求体 (转换后):")
            print(prettyJSON(transformedBody) ?? transformedBody)
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        // 根据是否流式选择处理路径
        if isStreaming {
            return try await handleStreamingRequest(upstreamRequest: upstreamRequest)
        }

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

    /// 处理流式请求
    private func handleStreamingRequest(upstreamRequest: URLRequest) async throws -> Response {
        let streamResult = try await networkService.sendStream(request: upstreamRequest)

        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"

        // 转发上游的相关 header
        if let httpResponse = streamResult.response as? HTTPURLResponse {
            for (key, value) in httpResponse.allHeaderFields {
                let keyString = (key as? String ?? "").lowercased()
                if keyString.hasPrefix("x-") || keyString == "request-id" {
                    if let name = HTTPField.Name(String(describing: key)) {
                        headers[name] = String(describing: value)
                    }
                }
            }
        }

        let body = ResponseBody(contentLength: nil) { writer in
            var buffer = ByteBuffer()
            buffer.reserveCapacity(8192)

            do {
                for try await chunk in streamResult.bytes.chunks(ofCount: 8192) {
                    buffer.clear()
                    buffer.writeBytes(chunk)
                    try await writer.write(buffer)
                }
                try await writer.finish(nil)
            } catch {
                print("[SSE] 流传输错误: \(error)")
                try await writer.finish(nil)
            }
        }

        return Response(status: .ok, headers: headers, body: body)
    }

    /// 格式化 JSON 字符串
    private func prettyJSON(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: jsonObject,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return prettyString
    }
}
