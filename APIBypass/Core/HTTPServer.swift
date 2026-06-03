import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import ServiceLifecycle

// MARK: - 流控与并发控制工具

/// 异步信号量，用于控制并发访问
actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

    /// 获取信号量，如果不可用则挂起
    func acquire() async {
        if value > 0 {
            value -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// 释放信号量
    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            value += 1
        }
    }

    /// 尝试获取信号量，如果不可用立即返回 false
    func tryAcquire() -> Bool {
        if value > 0 {
            value -= 1
            return true
        }
        return false
    }

    /// 当前可用许可数
    var availablePermits: Int { value }

    /// 等待中的任务数
    var waitingCount: Int { waiters.count }
}

@MainActor
final class HTTPServer: ObservableObject {
    private let configManager: ConfigManager
    private let keychain: KeychainService
    private let proxyEngine: ProxyEngine
    private let networkService: NetworkService
    private var app: Application<RouterResponder<BasicRequestContext>>?
    private var serviceGroup: ServiceGroup?

    let port: Int

    // MARK: - 并发控制

    /// 最大并发连接数
    private let maxConcurrentConnections: Int
    /// 连接信号量
    private var connectionSemaphore: AsyncSemaphore?
    /// 当前活跃连接数
    private var activeConnections: Int = 0
    private let connectionLock = NSLock()

    static var storedPort: Int {
        get { UserDefaults.standard.integer(forKey: "serverPort") }
        set { UserDefaults.standard.set(newValue, forKey: "serverPort") }
    }

    init(
        configManager: ConfigManager,
        keychain: KeychainService = .shared,
        maxConcurrentConnections: Int = 100
    ) {
        self.configManager = configManager
        self.keychain = keychain
        self.proxyEngine = ProxyEngine()
        self.networkService = NetworkService()
        let saved = UserDefaults.standard.integer(forKey: "serverPort")
        self.port = saved > 0 ? saved : 8390

        // 并发连接限制配置
        self.maxConcurrentConnections = maxConcurrentConnections
        self.connectionSemaphore = AsyncSemaphore(value: maxConcurrentConnections)
    }

    func start() async throws {
        let router = Router()

        // OpenAI 兼容端点（带并发限制）
        router.post("/v1/chat/completions") { [weak self] request, context in
            guard let self = self else {
                return Response(status: .internalServerError, body: .init(byteBuffer: ByteBuffer()))
            }
            return try await self.handleRequestWithConcurrencyLimit(request, context, format: .openai)
        }

        // Anthropic 端点（带并发限制）
        router.post("/v1/messages") { [weak self] request, context in
            guard let self = self else {
                return Response(status: .internalServerError, body: .init(byteBuffer: ByteBuffer()))
            }
            return try await self.handleRequestWithConcurrencyLimit(request, context, format: .anthropic)
        }

        // Responses 端点（带并发限制）
        router.post("/v1/responses") { [weak self] request, context in
            guard let self = self else {
                return Response(status: .internalServerError, body: .init(byteBuffer: ByteBuffer()))
            }
            return try await self.handleRequestWithConcurrencyLimit(request, context, format: .responses)
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

    // MARK: - 并发控制方法

    /// 带并发限制的请求处理器
    private func handleRequestWithConcurrencyLimit(
        _ request: Request,
        _ context: BasicRequestContext,
        format: APIFormat
    ) async throws -> Response {
        // 检查是否可以立即处理
        guard let semaphore = connectionSemaphore else {
            // 如果信号量未初始化，直接处理
            return try await handleProxyRequest(request, context, format: format)
        }

        // 尝试获取连接许可
        if await !semaphore.tryAcquire() {
            // 连接数已满，返回 503 服务不可用
            let errorResponse: [String: Any] = [
                "error": [
                    "message": "Server is at capacity. Please try again later.",
                    "type": "rate_limit_error",
                    "code": 503
                ]
            ]
            let errorData = try JSONSerialization.data(withJSONObject: errorResponse)
            return Response(
                status: .serviceUnavailable,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: errorData))
            )
        }

        // 已获取许可，处理请求
        incrementActiveConnections()
        do {
            let response = try await handleProxyRequest(request, context, format: format)
            decrementActiveConnections()
            await semaphore.release()
            return response
        } catch {
            decrementActiveConnections()
            await semaphore.release()
            throw error
        }
    }

    private func incrementActiveConnections() {
        connectionLock.lock()
        activeConnections += 1
        connectionLock.unlock()
    }

    private func decrementActiveConnections() {
        connectionLock.lock()
        activeConnections = max(0, activeConnections - 1)
        connectionLock.unlock()
    }

    /// 获取当前活跃连接数
    var currentActiveConnections: Int {
        connectionLock.lock()
        let count = activeConnections
        connectionLock.unlock()
        return count
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

        let path = provider.baseURL.path
        let hasVersionInPath = path.range(of: #"/v\d+"#, options: .regularExpression) != nil
        if hasVersionInPath || path.hasSuffix("/api") {
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

    /// 处理流式请求（带背压控制）
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
                print("[SSE] 开始发送流式请求到上游...")
                let streamResult = try await self.networkService.sendStream(request: upstreamRequest)
                print("[SSE] 上游连接成功，开始接收流数据...")

                if needsConversion {
                    let streamTranslator = StreamTranslator()
                    let convertedStream: AsyncThrowingStream<String, Error>
                    print("[SSE] 需要格式转换: \(upstreamFormat) → \(clientFormat)")
                    switch (upstreamFormat, clientFormat) {
                    case (.openai, .anthropic):
                        convertedStream = streamTranslator.translateOpenAIToAnthropic(bytes: streamResult.bytes, model: model)
                    case (.anthropic, .openai):
                        print("[SSE] 使用 translateAnthropicToOpenAI 转换器")
                        convertedStream = streamTranslator.translateAnthropicToOpenAI(bytes: streamResult.bytes, model: model)
                    case (.responses, .anthropic), (.responses, .openai), (.anthropic, .responses), (.openai, .responses):
                        print("[SSE] Responses streaming format translation not yet fully implemented, forwarding raw stream")
                        // 使用优化的批量读取
                        try await self.streamWithBackpressure(bytes: streamResult.bytes, writer: &writer)
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
                    // 使用优化的批量读取（无格式转换）
                    try await self.streamWithBackpressure(bytes: streamResult.bytes, writer: &writer)
                    try await writer.finish(nil)
                }
            } catch {
                print("[SSE] 流传输错误: \(error)")
                let errorResponse: [String: Any]
                if case ProxyError.upstreamError(let code, let data) = error {
                    let bodyStr = String(data: data ?? Data(), encoding: .utf8) ?? "unknown"
                    errorResponse = [
                        "error": [
                            "message": "Upstream \(code): \(bodyStr)",
                            "type": "upstream_error"
                        ]
                    ]
                } else {
                    errorResponse = [
                        "error": [
                            "message": error.localizedDescription,
                            "type": "proxy_error"
                        ]
                    ]
                }
                if let errorData = try? JSONSerialization.data(withJSONObject: errorResponse),
                   let errorJSON = String(data: errorData, encoding: .utf8) {
                    let sseError = "data: \(errorJSON)\n\ndata: [DONE]\n\n"
                    if let sseData = sseError.data(using: .utf8) {
                        let buf = ByteBuffer(data: sseData)
                        try await writer.write(buf)
                    }
                }
            }
        }

        return Response(status: .ok, headers: headers, body: body)
    }

    /// 带背压控制的流式传输
    private func streamWithBackpressure(
        bytes: URLSession.AsyncBytes,
        writer: inout any ResponseBodyWriter
    ) async throws {
        // 使用更大的缓冲区 (64KB) 进行批量读取
        let bufferSize = 65536
        var buffer = ByteBuffer()
        buffer.reserveCapacity(bufferSize)

        // 使用 Task 检查点来避免阻塞
        var byteCount = 0
        let checkpointInterval = 8192  // 每 8KB 检查一次背压
        var doneReceived = false  // 追踪是否收到 [DONE]

        for try await byte in bytes {
            buffer.writeInteger(byte)
            byteCount += 1

            // 遇到换行符或缓冲区满时写入
            if byte == UInt8(ascii: "\n") || buffer.readableBytes >= bufferSize {
                // 检查是否是 [DONE] 标记
                if let line = String(bytes: buffer.readableBytesView, encoding: .utf8),
                   line.contains("[DONE]") {
                    try await writer.write(buffer)
                    doneReceived = true
                    break  // 收到 [DONE] 后停止处理
                }
                try await writer.write(buffer)
                buffer.clear()
            }

            // 定期让出线程，避免阻塞
            if byteCount % checkpointInterval == 0 {
                await Task.yield()
            }
        }

        // 写入剩余数据（仅在未收到 [DONE] 时）
        if !doneReceived && buffer.readableBytes > 0 {
            try await writer.write(buffer)
        }
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
