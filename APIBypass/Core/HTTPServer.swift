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

    let port: Int

    static var storedPort: Int {
        get { UserDefaults.standard.integer(forKey: "serverPort") }
        set { UserDefaults.standard.set(newValue, forKey: "serverPort") }
    }

    init(configManager: ConfigManager, keychain: KeychainService = .shared) {
        self.configManager = configManager
        self.keychain = keychain
        self.proxyEngine = ProxyEngine()
        self.networkService = NetworkService()
        let saved = UserDefaults.standard.integer(forKey: "serverPort")
        self.port = saved > 0 ? saved : 8390
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

        router.post("/v1/responses") { [weak self] request, context in
            guard let self = self else {
                return Response(status: .internalServerError, body: .init(byteBuffer: ByteBuffer()))
            }
            return try await self.handleProxyRequest(request, context, format: .responses)
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

        // 获取提供商配置
        guard let provider = configManager.findProvider(for: mapping.providerConfigId) else {
            let errorData = #"{"error": "Provider not found for this mapping"}"#.data(using: .utf8)!
            return Response(
                status: .badRequest,
                body: .init(byteBuffer: ByteBuffer(data: errorData))
            )
        }

        // 检测是否为流式请求
        let isStreaming = (json["stream"] as? Bool) ?? false

        // 确定是否需要格式转换
        let upstreamFormat: APIFormat
        switch provider.apiProvider {
        case .openai: upstreamFormat = .openai
        case .anthropic: upstreamFormat = .anthropic
        case .openaiResponses: upstreamFormat = .responses
        }
        let needsConversion = format != upstreamFormat
        let effectiveFormat = needsConversion ? upstreamFormat : format

        // 转换请求（参数注入 + 模型名替换）
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

        // 格式转换（Anthropic ↔ OpenAI）
        let finalRequestData: Data
        if needsConversion {
            let translator = FormatTranslator()
            do {
                finalRequestData = try translator.translateRequest(transformedData, from: format, to: upstreamFormat)
            } catch {
                let errorData = #"{"error": "Format translation failed"}"#.data(using: .utf8)!
                return Response(
                    status: .internalServerError,
                    body: .init(byteBuffer: ByteBuffer(data: errorData))
                )
            }
        } else {
            finalRequestData = transformedData
        }

        // 获取 API Key
        let apiKey: String
        do {
            apiKey = try keychain.retrieve(forKey: mapping.providerConfigId.uuidString)
        } catch {
            let errorData = #"{"error": "API key not configured"}"#.data(using: .utf8)!
            return Response(
                status: .internalServerError,
                body: .init(byteBuffer: ByteBuffer(data: errorData))
            )
        }

        // 构建上游请求 URL（使用转换后的有效格式）
        let upstreamURL: URL
        let endpointPath: String
        switch effectiveFormat {
        case .openai: endpointPath = "chat/completions"
        case .anthropic: endpointPath = "messages"
        case .responses: endpointPath = "responses"
        }

        let urlPath = provider.baseURL.path
        let hasVersionInPath = urlPath.range(of: #"/v\d+"#, options: .regularExpression) != nil
        if hasVersionInPath || urlPath.hasSuffix("/api") {
            upstreamURL = provider.baseURL.appendingPathComponent(endpointPath)
        } else {
            upstreamURL = provider.baseURL.appendingPathComponent("v1").appendingPathComponent(endpointPath)
        }

        let upstreamRequest = networkService.buildRequest(
            url: upstreamURL,
            method: "POST",
            body: finalRequestData,
            apiKey: apiKey,
            provider: provider.apiProvider.transportFormat,
            customHeaders: mapping.parameters.customHeaders
        )

        // 日志: 转换后请求
        print("\n📤 转发到上游 API\(isStreaming ? " [流式模式]" : "")\(needsConversion ? " [格式转换: \(format) → \(upstreamFormat)]" : "")")
        print("────────────────────────────────────────────────────────────")
        print("上游 URL: \(upstreamURL.absoluteString)")
        print("实际模型: \(mapping.actualModel)")
        if let finalBody = String(data: finalRequestData, encoding: .utf8) {
            print("请求体 (转换后):")
            print(prettyJSON(finalBody) ?? finalBody)
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        // 根据是否流式选择处理路径
        if isStreaming {
            return try await handleStreamingRequest(
                upstreamRequest: upstreamRequest,
                needsConversion: needsConversion,
                upstreamFormat: upstreamFormat,
                clientFormat: format,
                model: mapping.actualModel
            )
        }

        do {
            let rectifierEnabled = mapping.parameters.rectifierEnabled ?? true
            let (finalResponseData, httpResponse) = try await sendWithRectifier(
                upstreamRequest: upstreamRequest,
                needsConversion: needsConversion,
                upstreamFormat: upstreamFormat,
                clientFormat: format,
                model: mapping.actualModel,
                rectifierEnabled: rectifierEnabled,
                apiKey: apiKey,
                provider: provider.apiProvider.transportFormat,
                customHeaders: mapping.parameters.customHeaders,
                baseURL: upstreamURL,
                actualModel: mapping.actualModel
            )

            print("📥 上游响应: \(httpResponse.statusCode)")
            if httpResponse.statusCode >= 300, let bodyStr = String(data: finalResponseData, encoding: .utf8) {
                print("📥 响应体: \(bodyStr)")
            }

            var headers = HTTPFields()
            for (key, value) in httpResponse.allHeaderFields {
                let keyString = (key as? String ?? "").lowercased()
                guard !["transfer-encoding", "connection", "content-length", "content-encoding", "keep-alive"].contains(keyString) else { continue }
                if let name = HTTPField.Name(String(describing: key)) {
                    headers[name] = String(describing: value)
                }
            }

            let statusCode = httpResponse.statusCode
            print("📤 返回客户端: \(statusCode), body 大小: \(finalResponseData.count) bytes")
            if let bodyStr = String(data: finalResponseData, encoding: .utf8) {
                print("📤 响应体: \(bodyStr.prefix(500))")
            }

            return Response(
                status: HTTPResponse.Status(code: statusCode),
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(data: finalResponseData))
            )
        } catch {
            print("❌ 上游请求失败: \(error)")
            let errorData = #"{"error": "Upstream API request failed"}"#.data(using: .utf8)!
            return Response(
                status: .badGateway,
                body: .init(byteBuffer: ByteBuffer(data: errorData))
            )
        }
    }

    /// 处理流式请求
    private func handleStreamingRequest(
        upstreamRequest: URLRequest,
        needsConversion: Bool,
        upstreamFormat: APIFormat,
        clientFormat: APIFormat,
        model: String
    ) async throws -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"

        let body = ResponseBody(contentLength: nil) { writer in
            do {
                let streamResult = try await self.networkService.sendStream(request: upstreamRequest)

                if needsConversion {
                    let streamTranslator = StreamTranslator()
                    let convertedStream: AsyncThrowingStream<String, Error>
                    switch (upstreamFormat, clientFormat) {
                    case (.openai, .anthropic):
                        convertedStream = streamTranslator.translateOpenAIToAnthropic(bytes: streamResult.bytes, model: model)
                    case (.anthropic, .openai):
                        convertedStream = streamTranslator.translateAnthropicToOpenAI(bytes: streamResult.bytes, model: model)
                    case (.responses, .anthropic), (.responses, .openai), (.anthropic, .responses), (.openai, .responses):
                        print("[SSE] Responses streaming format translation not yet fully implemented, forwarding raw stream")
                        var buffer = ByteBuffer()
                        buffer.reserveCapacity(1024)
                        for try await byte in streamResult.bytes {
                            buffer.writeInteger(byte)
                            if byte == UInt8(ascii: "\n") {
                                try await writer.write(buffer)
                                buffer.clear()
                            }
                        }
                        if buffer.readableBytes > 0 {
                            try await writer.write(buffer)
                        }
                        try await writer.finish(nil)
                        return
                    default:
                        try await writer.finish(nil)
                        return
                    }

                    for try await sseString in convertedStream {
                        if let stringData = sseString.data(using: .utf8) {
                            let buf = ByteBuffer(data: stringData)
                            try await writer.write(buf)
                        }
                    }
                    try await writer.finish(nil)
                } else {
                    var buffer = ByteBuffer()
                    buffer.reserveCapacity(1024)

                    for try await byte in streamResult.bytes {
                        buffer.writeInteger(byte)
                        if byte == UInt8(ascii: "\n") {
                            try await writer.write(buffer)
                            buffer.clear()
                        }
                    }
                    if buffer.readableBytes > 0 {
                        try await writer.write(buffer)
                    }
                    try await writer.finish(nil)
                }
            } catch {
                print("[SSE] 流传输错误: \(error)")
                let errorJSON: String
                if case ProxyError.upstreamError(let code, let data) = error {
                    let bodyStr = String(data: data ?? Data(), encoding: .utf8) ?? "unknown"
                    errorJSON = "{\"error\":{\"message\":\"Upstream \(code): \(bodyStr)\",\"type\":\"upstream_error\"}}"
                } else {
                    errorJSON = "{\"error\":{\"message\":\"\(error.localizedDescription)\",\"type\":\"proxy_error\"}}"
                }
                let sseError = "data: \(errorJSON)\n\ndata: [DONE]\n\n"
                if let errorData = sseError.data(using: .utf8) {
                    let buf = ByteBuffer(data: errorData)
                    try await writer.write(buf)
                }
                try await writer.finish(nil)
            }
        }

        return Response(status: .ok, headers: headers, body: body)
    }

    private func sendWithRectifier(
        upstreamRequest: URLRequest,
        needsConversion: Bool,
        upstreamFormat: APIFormat,
        clientFormat: APIFormat,
        model: String,
        rectifierEnabled: Bool,
        apiKey: String,
        provider: APIProvider,
        customHeaders: [String: String]?,
        baseURL: URL,
        actualModel: String
    ) async throws -> (Data, HTTPURLResponse) {
        let (responseData, response) = try await networkService.send(request: upstreamRequest)
        let httpResponse = response as! HTTPURLResponse

        if rectifierEnabled && (httpResponse.statusCode == 400 || httpResponse.statusCode == 422) {
            let errorBody = String(data: responseData, encoding: .utf8) ?? ""
            let translator = FormatTranslator()

            if translator.shouldRectifyThinkingSignature(errorBody) || translator.shouldRectifyThinkingBudget(errorBody) {
                print("🔄 Rectifier triggered for status \(httpResponse.statusCode), retrying with fixed request...")

                guard let originalBody = upstreamRequest.httpBody,
                      var bodyJson = try? JSONSerialization.jsonObject(with: originalBody) as? [String: Any] else {
                    return (responseData, httpResponse)
                }

                if translator.shouldRectifyThinkingSignature(errorBody) {
                    _ = translator.rectifyAnthropicRequest(&bodyJson)
                }
                if translator.shouldRectifyThinkingBudget(errorBody) {
                    _ = translator.rectifyThinkingBudget(&bodyJson)
                }

                let newBody = try JSONSerialization.data(withJSONObject: bodyJson)
                var newRequest = upstreamRequest
                newRequest.httpBody = newBody

                print("🔄 Rectifier retry request body:")
                if let bodyStr = String(data: newBody, encoding: .utf8) {
                    print(prettyJSON(bodyStr) ?? bodyStr)
                }

                let (retryData, retryResponse) = try await networkService.send(request: newRequest)
                let retryHttpResponse = retryResponse as! HTTPURLResponse

                if retryHttpResponse.statusCode < 300 {
                    print("✅ Rectifier retry succeeded")
                } else {
                    print("❌ Rectifier retry failed with status \(retryHttpResponse.statusCode)")
                }

                let finalData: Data
                if needsConversion {
                    finalData = try translator.translateResponse(retryData, from: upstreamFormat, to: clientFormat, model: model)
                } else {
                    finalData = retryData
                }
                return (finalData, retryHttpResponse)
            }
        }

        let finalData: Data
        if needsConversion {
            let translator = FormatTranslator()
            finalData = try translator.translateResponse(responseData, from: upstreamFormat, to: clientFormat, model: model)
        } else {
            finalData = responseData
        }
        return (finalData, httpResponse)
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
