import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import ServiceLifecycle
import CodexRouterCore

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

final class HTTPServer: ObservableObject {
    private let store = ConfigDataStore.shared
    private let keychain: KeychainService
    private let proxyEngine: ProxyEngine
    private let networkService: NetworkService
    private var app: Application<RouterResponder<BasicRequestContext>>?
    private var serviceGroup: ServiceGroup?
    private var serverTask: Task<Void, Never>?

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
        keychain: KeychainService = .shared,
        maxConcurrentConnections: Int = 100
    ) {
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

        // Responses API 端点（带并发限制）
        router.post("/v1/responses") { [weak self] request, context in
            guard let self = self else {
                return Response(status: .internalServerError, body: .init(byteBuffer: ByteBuffer()))
            }
            return try await self.handleRequestWithConcurrencyLimit(request, context, format: .responses)
        }

        // 模型列表端点
        router.get("/v1/models") { [weak self] request, context in
            let mappings = await self?.store.getMappings() ?? []
            let models = mappings.map { mapping in
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
        serverTask = Task {
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
        // 等待后台任务完成
        await serverTask?.value
        serverTask = nil
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

    private func injectStreamUsageIfNeeded(
        into data: Data,
        isStreaming: Bool,
        upstreamFormat: APIFormat,
        provider: ProviderConfig
    ) -> Data {
        guard isStreaming,
              upstreamFormat == .openai,
              provider.includeUsageInStreamRequests,
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["stream_options"] == nil else {
            return data
        }

        json["stream_options"] = ["include_usage": true]
        return (try? JSONSerialization.data(withJSONObject: json)) ?? data
    }

    private func handleProxyRequest(
        _ request: Request,
        _ context: BasicRequestContext,
        format: APIFormat
    ) async throws -> Response {
        let reqId = TraceLogger.newReqId()
        TraceLogger.shared.log(reqId, "━━━━━━━━━ NEW REQUEST [\(format == .openai ? "OpenAI" : "Anthropic")] ━━━━━━━━━")

        // 读取请求体
        let body = try await request.body.collect(upTo: 10 * 1024 * 1024)
        let data = Data(body.readableBytesView)

        // trace: 原始客户端请求体
        TraceLogger.shared.logBodyFull(reqId, label: "CLIENT REQUEST", data: data)
        let clientDumpPath = TraceLogger.debugDirectory.appendingPathComponent("client_\(reqId).json").path
        try? data.write(to: URL(fileURLWithPath: clientDumpPath))
        TraceLogger.shared.log(reqId, "client body dumped to: \(clientDumpPath)")

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
              let model = json["model"] as? String else {
            TraceLogger.shared.log(reqId, "❌ missing model field in request")
            let errorData = #"{"error": "Invalid request: missing model field"}"#.data(using: .utf8)!
            return Response(
                status: .badRequest,
                body: .init(byteBuffer: ByteBuffer(data: errorData))
            )
        }

        TraceLogger.shared.log(reqId, "incoming model: \(model)")

        // 从 ConfigDataStore 获取映射配置（线程安全）
        let mapping = await store.findMapping(for: model)

        guard let mapping else {
            TraceLogger.shared.log(reqId, "❌ no mapping for model \(model)")
            let errorData = #"{"error": "Model not found or no mapping configured"}"#.data(using: .utf8)!
            return Response(
                status: .badRequest,
                body: .init(byteBuffer: ByteBuffer(data: errorData))
            )
        }

        // 从 ConfigDataStore 获取提供商配置（线程安全）
        let provider = await store.findProvider(for: mapping.providerConfigId)

        guard let provider else {
            TraceLogger.shared.log(reqId, "❌ no provider for mapping \(mapping.id)")
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
        case .responses: upstreamFormat = .responses
        }

        // Responses API：检查兼容性，直接透传
        if format == .responses || upstreamFormat == .responses {
            guard format == upstreamFormat else {
                let errorMsg: String
                if format == .responses {
                    errorMsg = "Responses API endpoint requires a Responses API provider. Please configure a provider with API type 'Responses API'."
                } else {
                    errorMsg = "This provider only supports /v1/responses endpoint. Please use the Responses API endpoint instead."
                }
                let errorData = #"{"error": "\#(errorMsg)"}"#.data(using: .utf8)!
                return Response(status: .badRequest, body: .init(byteBuffer: ByteBuffer(data: errorData)))
            }
            // 直接透传，跳过格式转换
        }

        // 读取 bypassMode 状态
        let bypassMode = UserDefaults.standard.bool(forKey: "bypassMode")
        let preserveModel = UserDefaults.standard.bool(forKey: "preserveIncomingModel")
        let needsConversion = !bypassMode && (format != upstreamFormat)
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
                let thinkingConfig = (mapping.parameters.thinkingOverrideEnabled == true) ? mapping.parameters.thinking : nil
                finalRequestData = try translator.translateRequest(transformedData, from: format, to: upstreamFormat, thinkingConfig: thinkingConfig)
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

        let upstreamRequestData = injectStreamUsageIfNeeded(
            into: finalRequestData,
            isStreaming: isStreaming,
            upstreamFormat: upstreamFormat,
            provider: provider
        )

        // 获取 API Key
        let apiKey: String
        do {
            apiKey = try await keychain.retrieve(forKey: mapping.providerConfigId.uuidString)
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
            body: upstreamRequestData,
            apiKey: apiKey,
            provider: provider.apiProvider.transportFormat,
            customHeaders: mapping.parameters.customHeaders
        )

        // 日志: 转换后请求
        let modeTag = bypassMode ? " [纯代理模式]" : (needsConversion ? " [格式转换: \(format) → \(upstreamFormat)]" : "")
        print("\n📤 转发到上游 API\(isStreaming ? " [流式模式]" : "")\(modeTag)")
        print("────────────────────────────────────────────────────────────")
        print("上游 URL: \(upstreamURL.absoluteString)")
        print("实际模型: \(mapping.actualModel)")

        // trace: 上游请求
        TraceLogger.shared.log(reqId, "upstream_url: \(upstreamURL.absoluteString)")
        TraceLogger.shared.log(reqId, "upstream_model: \(mapping.actualModel) (from incoming=\(mapping.incomingModel))")
        TraceLogger.shared.log(reqId, "mode: stream=\(isStreaming) bypass=\(bypassMode) needsConversion=\(needsConversion) upstreamFormat=\(upstreamFormat) clientFormat=\(format)")
        TraceLogger.shared.logBodyFull(reqId, label: "UPSTREAM REQUEST", data: upstreamRequestData)

        // 同时把 upstream body 写到独立文件，方便 curl 直连复现
        let dumpPath = TraceLogger.debugDirectory.appendingPathComponent("upstream_\(reqId).json").path
        try? upstreamRequestData.write(to: URL(fileURLWithPath: dumpPath))
        TraceLogger.shared.log(reqId, "upstream body dumped to: \(dumpPath)")

        if let finalBody = String(data: upstreamRequestData, encoding: .utf8) {
            print("请求体 (转换后):")
            print(prettyJSON(finalBody) ?? finalBody)
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        // 根据是否流式选择处理路径
        if isStreaming {
            let responseModel = preserveModel ? mapping.incomingModel : mapping.actualModel
            return try await handleStreamingRequest(
                upstreamRequest: upstreamRequest,
                needsConversion: needsConversion,
                upstreamFormat: upstreamFormat,
                clientFormat: format,
                model: responseModel,
                preserveModel: preserveModel,
                actualModel: mapping.actualModel,
                incomingModel: mapping.incomingModel,
                reqId: reqId
            )
        }

        do {
            let rectifierEnabled = mapping.parameters.rectifierEnabled ?? true
            let responseModel = preserveModel ? mapping.incomingModel : mapping.actualModel
            let (finalResponseData, httpResponse) = try await sendWithRectifier(
                upstreamRequest: upstreamRequest,
                needsConversion: needsConversion,
                upstreamFormat: upstreamFormat,
                clientFormat: format,
                model: responseModel,
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
            let outputData = preserveModel ? replaceModelInResponseData(finalResponseData, with: mapping.incomingModel) : finalResponseData
            print("📤 返回客户端: \(statusCode), body 大小: \(outputData.count) bytes")
            if let bodyStr = String(data: outputData, encoding: .utf8) {
                print("📤 响应体: \(bodyStr.prefix(500))")
            }

            return Response(
                status: HTTPResponse.Status(code: statusCode),
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(data: outputData))
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
        model: String,
        preserveModel: Bool = false,
        actualModel: String = "",
        incomingModel: String = "",
        reqId: String = "none"
    ) async throws -> Response {
        // Try streaming request, handle retryable param errors
        let streamResult: StreamingResult
        do {
            // Log the first request body
            if let body = upstreamRequest.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
                TraceLogger.shared.log(reqId, "━━━ FIRST REQUEST BODY (\(body.count) bytes) ━━━")
                TraceLogger.shared.log(reqId, bodyStr)
            }
            print("[SSE] 开始发送流式请求到上游...")
            TraceLogger.shared.log(reqId, "━━━ UPSTREAM SSE (raw chunks from \(upstreamFormat)) ━━━")
            streamResult = try await self.networkService.sendStream(request: upstreamRequest)
            print("[SSE] 上游连接成功，开始接收流数据...")
            TraceLogger.shared.log(reqId, "upstream connection established")
        } catch ProxyError.upstreamError(let code, let data) where code == 400 {
            // Log the error details first
            let errorBodyString = String(data: data ?? Data(), encoding: .utf8) ?? "unknown"
            TraceLogger.shared.log(reqId, "❌ First request failed with 400: \(errorBodyString)")

            // Check if this is a retryable param error
            guard let errorData = data,
                  let action = parseParamErrorAction(status: 400, errorBody: errorData),
                  let requestBody = upstreamRequest.httpBody,
                  let json = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any] else {
                // Not retryable - return error response
                TraceLogger.shared.log(reqId, "❌ Not retryable error")
                return Self.makeSSEErrorResponse(status: 400, errorBody: data)
            }

            // Apply the action to modify request
            let modifiedJSON = Self.applyParamErrorAction(action, to: json, reqId: reqId)
            guard let modifiedBody = try? JSONSerialization.data(withJSONObject: modifiedJSON) else {
                return Self.makeSSEErrorResponse(status: 400, errorBody: data)
            }

            // Log the retry request body
            if let bodyStr = String(data: modifiedBody, encoding: .utf8) {
                TraceLogger.shared.log(reqId, "━━━ RETRY REQUEST BODY (\(modifiedBody.count) bytes) ━━━")
                TraceLogger.shared.log(reqId, bodyStr)
            }

            // Retry with modified request
            var retryRequest = upstreamRequest
            retryRequest.httpBody = modifiedBody
            TraceLogger.shared.log(reqId, "🔄 Retrying with modified parameters")

            do {
                streamResult = try await self.networkService.sendStream(request: retryRequest)
                TraceLogger.shared.log(reqId, "✅ Retry successful")
            } catch {
                // Retry failed - return error
                if case ProxyError.upstreamError(let retryCode, let retryData) = error {
                    TraceLogger.shared.log(reqId, "❌ Retry failed with status \(retryCode)")
                    return Self.makeSSEErrorResponse(status: retryCode, errorBody: retryData)
                }
                throw error
            }
        } catch {
            // Non-retryable error
            if case ProxyError.upstreamError(let code, let data) = error {
                TraceLogger.shared.log(reqId, "❌ upstream error \(code): \(String(data: data ?? Data(), encoding: .utf8) ?? "unknown")")
                return Self.makeSSEErrorResponse(status: code, errorBody: data)
            }
            throw error
        }

        // Create streaming response with successful stream
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"

        let body = ResponseBody(contentLength: nil) { writer in
            do {
                if needsConversion {
                    let streamTranslator = StreamTranslator()
                    let convertedStream: AsyncThrowingStream<String, Error>
                    print("[SSE] 需要格式转换: \(upstreamFormat) → \(clientFormat)")
                    TraceLogger.shared.log(reqId, "━━━ TRANSLATED SSE (→ \(clientFormat)) ━━━")
                    switch (upstreamFormat, clientFormat) {
                    case (.openai, .anthropic):
                        convertedStream = streamTranslator.translateOpenAIToAnthropic(bytes: streamResult.bytes, model: model, reqId: reqId)
                    case (.anthropic, .openai):
                        print("[SSE] 使用 translateAnthropicToOpenAI 转换器")
                        convertedStream = streamTranslator.translateAnthropicToOpenAI(bytes: streamResult.bytes, model: model)
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
                    if preserveModel {
                        try await self.streamWithBackpressure(
                            bytes: streamResult.bytes,
                            writer: &writer,
                            modelReplacement: (from: actualModel, to: incomingModel),
                            reqId: reqId
                        )
                    } else {
                        try await self.streamWithBackpressure(bytes: streamResult.bytes, writer: &writer, reqId: reqId)
                    }
                    try await writer.finish(nil)
                }
            } catch {
                print("[SSE] 流传输错误: \(error)")
                TraceLogger.shared.log(reqId, "❌ STREAM ERROR: \(error)")
                let errorResponse: [String: Any]
                if case ProxyError.upstreamError(let code, let data) = error {
                    let bodyStr = String(data: data ?? Data(), encoding: .utf8) ?? "unknown"
                    print("[SSE] upstream error body: \(bodyStr)")
                    TraceLogger.shared.log(reqId, "❌ upstream error \(code): \(bodyStr.prefix(500))")
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

    /// Create an SSE error response
    private static func makeSSEErrorResponse(status: Int, errorBody: Data?) -> Response {
        let bodyStr = String(data: errorBody ?? Data(), encoding: .utf8) ?? "unknown"
        let errorResponse: [String: Any] = [
            "error": [
                "message": "Upstream \(status): \(bodyStr)",
                "type": "upstream_error"
            ]
        ]
        let sseError: String
        if let errorData = try? JSONSerialization.data(withJSONObject: errorResponse),
           let errorJSON = String(data: errorData, encoding: .utf8) {
            sseError = "data: \(errorJSON)\n\ndata: [DONE]\n\n"
        } else {
            sseError = "data: {\"error\":{\"type\":\"upstream_error\"}}\n\ndata: [DONE]\n\n"
        }
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(string: sseError)))
    }

    /// Apply ParamErrorAction to request body JSON
    private static func applyParamErrorAction(_ action: ParamErrorAction, to json: [String: Any], reqId: String) -> [String: Any] {
        var result = json
        switch action {
        case .remove(let param):
            let oldValue = result[param]
            result.removeValue(forKey: param)
            print("[SSE] 🔄 Removed parameter: \(param) (was: \(oldValue ?? "nil"))")
            TraceLogger.shared.log(reqId, "🔄 Removed parameter: \(param) (was: \(oldValue ?? "nil"))")
        case .replace(let oldParam, let newParam):
            if let value = result[oldParam] {
                result.removeValue(forKey: oldParam)
                result[newParam] = value
                print("[SSE] 🔄 Replaced \(oldParam) → \(newParam)")
                TraceLogger.shared.log(reqId, "🔄 Replaced \(oldParam) → \(newParam)")
            }
        }
        return result
    }

    /// 带背压控制的流式传输
    private func streamWithBackpressure(
        bytes: URLSession.AsyncBytes,
        writer: inout any ResponseBodyWriter,
        modelReplacement: (from: String, to: String)? = nil,
        reqId: String = "unknown"
    ) async throws {
        // 使用更大的缓冲区 (64KB) 进行批量读取
        let bufferSize = 65536
        var buffer = ByteBuffer()
        buffer.reserveCapacity(bufferSize)

        // 使用 Task 检查点来避免阻塞
        var byteCount = 0
        let checkpointInterval = 8192  // 每 8KB 检查一次背压
        var doneReceived = false  // 追踪是否收到 [DONE]

        // 聚合响应内容用于日志记录
        var responseBuffer = Data()
        let maxLogSize = 100000  // 最多记录 100KB 响应

        for try await byte in bytes {
            buffer.writeInteger(byte)
            byteCount += 1

            // 遇到换行符或缓冲区满时写入
            if byte == UInt8(ascii: "\n") || buffer.readableBytes >= bufferSize {
                // 检查是否是 [DONE] 标记
                if let line = String(bytes: buffer.readableBytesView, encoding: .utf8),
                   line.contains("[DONE]") {
                    // 记录响应
                    if let lineStr = String(bytes: buffer.readableBytesView, encoding: .utf8) {
                        TraceLogger.shared.log(reqId, "📥 SSE EVENT: \(lineStr.prefix(500))")
                    }
                    try await writer.write(buffer)
                    doneReceived = true
                    break  // 收到 [DONE] 后停止处理
                }

                // 记录每个 SSE 事件
                if let lineStr = String(bytes: buffer.readableBytesView, encoding: .utf8), !lineStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // 只记录有意义的行（data: 或 event: 开头的）
                    if lineStr.hasPrefix("data:") || lineStr.hasPrefix("event:") {
                        TraceLogger.shared.log(reqId, "📥 SSE EVENT: \(lineStr.prefix(500))")
                        // 聚合到响应缓冲区
                        if responseBuffer.count < maxLogSize {
                            responseBuffer.append(contentsOf: buffer.readableBytesView)
                        }
                    }
                }

                // 替换模型名称（如果需要）
                var outputBuffer = buffer
                if let replacement = modelReplacement {
                    outputBuffer = Self.replaceModelInBuffer(buffer, from: replacement.from, to: replacement.to)
                }

                try await writer.write(outputBuffer)
                buffer.clear()
            }

            // 定期让出线程，避免阻塞
            if byteCount % checkpointInterval == 0 {
                await Task.yield()
            }
        }

        // 写入剩余数据（仅在未收到 [DONE] 时）
        if !doneReceived && buffer.readableBytes > 0 {
            var outputBuffer = buffer
            if let replacement = modelReplacement {
                outputBuffer = Self.replaceModelInBuffer(buffer, from: replacement.from, to: replacement.to)
            }
            try await writer.write(outputBuffer)
        }

        // 记录聚合的响应体
        if !responseBuffer.isEmpty {
            TraceLogger.shared.log(reqId, "━━━ RESPONSE BODY (\(responseBuffer.count) bytes aggregated) ━━━")
            if let responseStr = String(data: responseBuffer, encoding: .utf8) {
                let truncated = String(responseStr.prefix(maxLogSize))
                TraceLogger.shared.log(reqId, truncated)
            }
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

    /// 替换响应 JSON 中的 model 字段
    private func replaceModelInResponseData(_ data: Data, with model: String) -> Data {
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        if json["model"] != nil {
            json["model"] = model
            return (try? JSONSerialization.data(withJSONObject: json)) ?? data
        }
        return data
    }

    /// 替换 ByteBuffer 中的模型名称（用于流式传输）
    private static func replaceModelInBuffer(_ buffer: ByteBuffer, from: String, to: String) -> ByteBuffer {
        guard let string = String(data: Data(buffer.readableBytesView), encoding: .utf8) else { return buffer }
        let patterns = [
            ("\"model\":\"\(from)\"", "\"model\":\"\(to)\""),
            ("\"model\": \"\(from)\"", "\"model\": \"\(to)\"")
        ]
        var modified = string
        for (search, replace) in patterns {
            modified = modified.replacingOccurrences(of: search, with: replace)
        }
        if modified != string, let data = modified.data(using: .utf8) {
            return ByteBuffer(data: data)
        }
        return buffer
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
