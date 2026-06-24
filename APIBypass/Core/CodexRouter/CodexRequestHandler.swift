import Foundation
import Hummingbird
import NIOCore
import CodexRouterCore

/// Chat Completions fields to pass through from Responses request.
private let extraChatPassthroughFields: Set<String> = [
    "frequency_penalty", "logit_bias", "logprobs", "metadata", "n",
    "parallel_tool_calls", "presence_penalty", "response_format", "seed",
    "service_tier", "stop", "stream_options", "top_logprobs", "user"
]

/// Handles incoming proxy requests and forwards them to upstream providers.
/// Uses CodexConfigService as the SINGLE source of truth for configuration.
actor CodexRequestHandler {
    private let reasoningRectifier: ReasoningRectifier
    private let chatToResponsesTransformer: ChatToResponsesTransformer
    private let responsesToChatTransformer: ResponsesToChatTransformer
    private let httpClient: HTTPClient

    init() {
        self.reasoningRectifier = ReasoningRectifier()
        self.chatToResponsesTransformer = ChatToResponsesTransformer()
        self.responsesToChatTransformer = ResponsesToChatTransformer()
        self.httpClient = HTTPClient()
    }

    /// Build the OpenAI-compatible `/v1/models` response body from the local catalog.
    /// Pure function — does not touch the network or singletons, safe to unit-test.
    /// - Returns: `{"object":"list","data":[{"id":...,"object":"model","owned_by":"apibypass"}]}`
    static func makeModelsListBody(catalog: ModelCatalog?) -> Data {
        let entries = catalog?.models ?? []
        let data: [[String: Any]] = entries.map { entry in
            [
                "id": entry.displayName ?? entry.model,
                "object": "model",
                "owned_by": "apibypass"
            ]
        }
        let body: [String: Any] = ["object": "list", "data": data]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    /// Wrap the models-list body in an HTTP 200 Hummingbird Response.
    static func makeModelsListResponse(catalog: ModelCatalog?) -> Response {
        let body = makeModelsListBody(catalog: catalog)
        return Response(
            status: .ok,
            body: .init(byteBuffer: ByteBuffer(data: body))
        )
    }

    /// Handle a proxy request.
    func handle(
        request: Request,
        endpoint: ProxyEndpoint
    ) async throws -> Response {
        // `.models` always returns the local catalog — never forward to upstream.
        // This keeps Codex's model selector populated even when the upstream is
        // unreachable or the user is not logged in.
        if endpoint == .models {
            let provider = try? CodexConfigService.shared.getCurrentUpstreamProvider()
            return Self.makeModelsListResponse(catalog: provider?.modelCatalog)
        }

        guard let provider = try CodexConfigService.shared.getCurrentUpstreamProvider() else {
            return Response(
                status: .serviceUnavailable,
                body: .init(byteBuffer: ByteBuffer(string: #"{"error":"No provider configured in ~/.codex/config.toml"}"#))
            )
        }

        return try await forwardRequest(request: request, provider: provider, endpoint: endpoint)
    }

    /// Forward request to upstream provider.
    private func forwardRequest(
        request: Request,
        provider: UpstreamProvider,
        endpoint: ProxyEndpoint
    ) async throws -> Response {
        // Build upstream URL
        let upstreamURL = provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + endpoint.upstreamPath(usesChatCompletions: provider.usesChatCompletions)

        CodexLogStore.shared.info("[CodexRouter] Upstream URL: \(upstreamURL)")
        CodexLogStore.shared.info("[CodexRouter] usesChatCompletions: \(provider.usesChatCompletions)")

        // Build headers
        var headers: [String: String] = [:]
        headers["Content-Type"] = "application/json"
        if let token = provider.bearerToken {
            headers["Authorization"] = "Bearer \(token)"
        }

        // Parse request body for POST requests
        var requestBody: Data?
        var bodyBuffer = ByteBuffer()
        for try await chunk in request.body {
            var mutableChunk = chunk
            bodyBuffer.writeBuffer(&mutableChunk)
        }
        if bodyBuffer.readableBytes > 0 {
            requestBody = Data(buffer: bodyBuffer)
            if let bodyString = String(data: requestBody!, encoding: .utf8) {
                CodexLogStore.shared.info("[CodexRouter] Request body: \(bodyString.prefix(500))")
            }
        }

        // Parse JSON
        var requestJSON: [String: Any]?
        if let data = requestBody,
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            // Build tool context from original Responses body (before Chat conversion)
            let toolContext = CodexToolContext(responsesBody: json)

            // Resolve Codex model name → APIBypass model name via the provider's model catalog
            let rawModelName = json["model"] as? String ?? ""
            var modelName = rawModelName
            if let catalog = provider.modelCatalog {
                if let entry = catalog.models.first(where: { $0.displayName == rawModelName }) {
                    modelName = entry.model
                    json["model"] = modelName
                    CodexLogStore.shared.info("[CodexRouter] Model resolved: '\(rawModelName)' → '\(modelName)'")
                } else if catalog.models.contains(where: { $0.model == rawModelName }) {
                    // Already resolved, no change needed
                }
            }

            // Resolve reasoning config: explicit config takes priority, otherwise auto-infer
            let resolvedReasoningConfig = provider.reasoningConfig?.normalized()
                ?? ReasoningConfig.infer(name: provider.name, baseURL: provider.baseURL, model: modelName)
            if let rc = resolvedReasoningConfig {
                CodexLogStore.shared.info("[CodexRouter] Resolved reasoning config: thinking=\(rc.supportsThinking ?? false) effort=\(rc.supportsEffort ?? false) thinkingParam=\(rc.thinkingParam ?? "nil") effortParam=\(rc.effortParam ?? "nil") mode=\(rc.effortValueMode ?? "nil")")
            }

            // Transform request from Responses to Chat format if needed (reasoning applied during conversion)
            if endpoint == .responses && provider.usesChatCompletions {
                CodexLogStore.shared.info("[CodexRouter] Transforming Responses request to Chat Completions")
                json = transformResponsesRequestToChat(json, toolContext: toolContext, reasoningConfig: resolvedReasoningConfig, model: modelName)
            }

            requestJSON = json
            requestBody = try? JSONSerialization.data(withJSONObject: json)
            if let body = requestBody, let str = String(data: body, encoding: .utf8) {
                CodexLogStore.shared.info("[CodexRouter] Transformed request body: \(str.prefix(500))")
            }

            // Determine if streaming
            let isStreaming = requestJSON?["stream"] as? Bool ?? false

            // Send request
            do {
                if isStreaming {
                    return try await handleStreamingRequest(
                        url: upstreamURL, headers: headers, body: requestBody,
                        provider: provider, endpoint: endpoint, toolContext: toolContext
                    )
                } else {
                    let (data, status) = try await httpClient.send(
                        url: upstreamURL, method: .post, headers: headers, body: requestBody
                    )
                    let transformedData = transformResponse(
                        data: data, provider: provider, endpoint: endpoint,
                        toolContext: toolContext, reasoningConfig: resolvedReasoningConfig
                    )
                    return Response(status: status, body: .init(byteBuffer: ByteBuffer(data: transformedData)))
                }
            } catch {
                return Response(
                    status: .badGateway,
                    body: .init(byteBuffer: ByteBuffer(string: #"{"error":"\#(error.localizedDescription)"}"#))
                )
            }
        } else {
            // No JSON body — forward as-is
            do {
                let (data, status) = try await httpClient.send(
                    url: upstreamURL, method: .post, headers: headers, body: requestBody
                )
                return Response(status: status, body: .init(byteBuffer: ByteBuffer(data: data)))
            } catch {
                return Response(
                    status: .badGateway,
                    body: .init(byteBuffer: ByteBuffer(string: #"{"error":"\#(error.localizedDescription)"}"#))
                )
            }
        }
    }

    /// Handle streaming request.
    private func handleStreamingRequest(
        url: String, headers: [String: String], body: Data?,
        provider: UpstreamProvider, endpoint: ProxyEndpoint,
        toolContext: CodexToolContext
    ) async throws -> Response {
        let needsTransformation = provider.usesChatCompletions && endpoint == .responses
        CodexLogStore.shared.info("[CodexRouter] Streaming request to \(url), needsTransformation: \(needsTransformation)")

        let streamingResponse = try await httpClient.sendStreaming(
            url: url, method: .post, headers: headers, body: body
        )
        CodexLogStore.shared.info("[CodexRouter] Upstream status: \(streamingResponse.status.code)")

        var responseHeaders = HTTPFields()
        responseHeaders[.contentType] = "text/event-stream"
        responseHeaders[.cacheControl] = "no-cache"
        responseHeaders[.connection] = "keep-alive"

        if needsTransformation {
            let transformer = ChatToResponsesStreamTransformer(toolContext: toolContext)
            var isFirstChunk = true

            let eventSequence = AsyncStream<ByteBuffer> { continuation in
                Task {
                    for await data in streamingResponse.events {
                        if isFirstChunk {
                            isFirstChunk = false
                            if let raw = String(data: data, encoding: .utf8) {
                                CodexLogStore.shared.info("[CodexRouter] First raw upstream chunk: \(raw.prefix(500))")
                            }
                        }
                        if let transformedData = await transformer.transform(data) {
                            continuation.yield(ByteBuffer(data: transformedData))
                        } else {
                            continuation.yield(ByteBuffer(data: data))
                        }
                    }
                    // Stream ended — send completion events
                    if let finalData = await transformer.finish(),
                       let final = String(data: finalData, encoding: .utf8) {
                        CodexLogStore.shared.info("[CodexRouter] Final flush: \(final.prefix(200))")
                        continuation.yield(ByteBuffer(data: finalData))
                    }
                    continuation.finish()
                }
            }

            let streamingBody = ResponseBody(asyncSequence: eventSequence)
            return Response(status: streamingResponse.status, headers: responseHeaders, body: streamingBody)
        } else {
            let eventSequence = streamingResponse.events.map { ByteBuffer(data: $0) }
            let streamingBody = ResponseBody(asyncSequence: eventSequence)
            return Response(status: streamingResponse.status, headers: responseHeaders, body: streamingBody)
        }
    }

    /// Transform response based on endpoint and provider.
    /// Includes error response normalization per cc-switch's chat_error_to_response_error.
    private func transformResponse(
        data: Data, provider: UpstreamProvider, endpoint: ProxyEndpoint,
        toolContext: CodexToolContext, reasoningConfig: ReasoningConfig?
    ) -> Data {
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }

        // If upstream returned an error, normalize to Responses API error format
        if json["error"] != nil || json["type"] as? String == "error" {
            return try! JSONSerialization.data(withJSONObject: chatErrorToResponseError(json))
        }

        // Apply response rectification (output format transformation)
        if let rc = reasoningConfig {
            reasoningRectifier.rectifyResponseWithConfig(&json, config: rc)
        } else {
            let platform = ReasoningPlatform.detect(from: provider.baseURL)
            reasoningRectifier.rectifyResponse(&json, platform: platform)
        }

        // Transform format if needed
        if provider.usesChatCompletions && endpoint == .responses {
            do {
                let rectifiedData = try JSONSerialization.data(withJSONObject: json)
                let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: rectifiedData)
                let responsesAPI = chatToResponsesTransformer.transform(
                    chatResponse: chatResponse, toolContext: toolContext
                )
                return try JSONEncoder().encode(responsesAPI)
            } catch {
                CodexLogStore.shared.info("[CodexRouter] Failed to transform Chat to Responses: \(error)")
                return data
            }
        } else if !provider.usesChatCompletions && endpoint == .chatCompletions {
            do {
                let jsonString = String(data: data, encoding: .utf8) ?? "{}"
                let chatResponse = try responsesToChatTransformer.transform(responsesJSON: jsonString)
                return try JSONEncoder().encode(chatResponse)
            } catch {
                return data
            }
        }

        return (try? JSONSerialization.data(withJSONObject: json)) ?? data
    }

    // MARK: - Responses → Chat Completions transformation

    /// Transform Responses API request to Chat Completions format.
    /// Follows cc-switch's responses_to_chat_completions_with_reasoning exactly.
    /// Reasoning is applied to the Chat-format request (not the original Responses format).
    private func transformResponsesRequestToChat(
        _ json: [String: Any],
        toolContext: CodexToolContext,
        reasoningConfig: ReasoningConfig?,
        model: String
    ) -> [String: Any] {
        var result: [String: Any] = [:]

        // 1. Copy model
        if let m = json["model"] { result["model"] = m }

        // 2. Build messages from input + instructions
        var messages: [[String: Any]] = []

        // instructions → system message
        if let instructions = json["instructions"] {
            let text = instructionText(instructions)
            if !text.isEmpty {
                messages.append(["role": "system", "content": text])
            }
        }

        // input → messages
        if let input = json["input"] {
            appendResponsesInputAsChatMessages(input, messages: &messages, toolContext: toolContext)
        }

        // Collapse system messages to head (MiniMax compat)
        messages = collapseSystemMessagesToHead(messages)
        result["messages"] = messages

        // 3. Max tokens: max_output_tokens → max_tokens or max_completion_tokens for o-series
        if let maxTokens = json["max_output_tokens"] {
            if isOpenAIOseries(model: model) {
                result["max_completion_tokens"] = maxTokens
            } else {
                result["max_tokens"] = maxTokens
            }
        }
        if let maxTokens = json["max_tokens"] { result["max_tokens"] = maxTokens }
        if let maxTokens = json["max_completion_tokens"] { result["max_completion_tokens"] = maxTokens }

        // 4. temperature, top_p, stream
        for key in ["temperature", "top_p", "stream"] {
            if let value = json[key] { result[key] = value }
        }

        // 5. Apply reasoning options (reads from original Responses body, writes to Chat request)
        reasoningRectifier.applyReasoning(
            chatRequest: &result,
            responsesBody: json,
            config: reasoningConfig,
            model: model
        )

        // 6. Tools from tool context
        let tools = toolContext.chatTools
        if !tools.isEmpty {
            result["tools"] = tools
        }

        // 7. tool_choice conversion
        if let toolChoice = json["tool_choice"] {
            result["tool_choice"] = responsesToolChoiceToChat(toolChoice, toolContext: toolContext)
        }

        // 8. Passthrough fields
        for key in extraChatPassthroughFields {
            if let value = json[key] { result[key] = value }
        }

        // 9. Drop tool_choice and parallel_tool_calls if no tools (strict upstreams reject this)
        let hasTools = (result["tools"] as? [[String: Any]])?.isEmpty == false
        if !hasTools {
            result.removeValue(forKey: "tool_choice")
            result.removeValue(forKey: "parallel_tool_calls")
        }

        // 10. Inject stream_options.include_usage for streaming (ensures usage/token tracking)
        injectOpenAIStreamIncludeUsage(&result)

        return result
    }

    // MARK: - Instruction text extraction

    private func instructionText(_ value: Any) -> String {
        if let text = value as? String { return text }
        if let parts = value as? [[String: Any]] {
            return parts.compactMap { part in
                part["text"] as? String
            }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        if let dict = value as? [String: Any], let text = dict["text"] as? String { return text }
        return ""
    }

    // MARK: - Input → Messages conversion (follows cc-switch)

    private func appendResponsesInputAsChatMessages(
        _ input: Any,
        messages: inout [[String: Any]],
        toolContext: CodexToolContext
    ) {
        var pendingToolCalls: [[String: Any]] = []
        var pendingReasoning: String?
        var lastAssistantIndex: Int?

        func flushPending() {
            guard !pendingToolCalls.isEmpty else { return }
            var message: [String: Any] = [
                "role": "assistant",
                "content": NSNull(),
                "tool_calls": pendingToolCalls
            ]
            attachPendingReasoning(&message, &pendingReasoning)
            lastAssistantIndex = messages.count
            messages.append(message)
            pendingToolCalls = []
        }

        if let text = input as? String {
            messages.append(["role": "user", "content": text])
        } else if let items = input as? [[String: Any]] {
            for item in items {
                let itemType = item["type"] as? String
                switch itemType {
                case "function_call":
                    appendUniqueReasoning(&pendingReasoning, responsesItemReasoningText(item))
                    pendingToolCalls.append(responsesFunctionCallToChatToolCall(item, toolContext: toolContext))
                case "custom_tool_call":
                    appendUniqueReasoning(&pendingReasoning, responsesItemReasoningText(item))
                    pendingToolCalls.append(responsesCustomToolCallToChat(item))
                case "tool_search_call":
                    appendUniqueReasoning(&pendingReasoning, responsesItemReasoningText(item))
                    pendingToolCalls.append(responsesToolSearchCallToChat(item))
                case "function_call_output":
                    flushPending()
                    let callId = item["call_id"] as? String ?? ""
                    let output = canonicalizeJSONString(item["output"] ?? "")
                    messages.append(["role": "tool", "tool_call_id": callId, "content": output])
                case "custom_tool_call_output", "tool_search_output":
                    flushPending()
                    let callId = item["call_id"] as? String ?? ""
                    let output = canonicalizeJSONString(item)
                    messages.append(["role": "tool", "tool_call_id": callId, "content": output])
                case "reasoning":
                    let reasoning = responsesReasoningItemText(item)
                    if pendingToolCalls.isEmpty {
                        if !attachReasoningToLastAssistant(&messages, lastAssistantIndex, reasoning) {
                            appendReasoning(&pendingReasoning, reasoning)
                        }
                    } else {
                        appendReasoning(&pendingReasoning, reasoning)
                    }
                case "input_text", "input_image", "input_file", "input_audio":
                    flushPending()
                    let role = responsesRoleToChatRole(item["role"] as? String)
                    let message: [String: Any] = [
                        "role": role,
                        "content": responsesContentToChatContent(role, [item])
                    ]
                    if role == "assistant" {
                        var msg = message
                        attachPendingReasoning(&msg, &pendingReasoning)
                        lastAssistantIndex = messages.count
                        messages.append(msg)
                    } else {
                        pendingReasoning = nil
                        lastAssistantIndex = messages.count
                        messages.append(message)
                    }
                case "message", nil:
                    // cc-switch: message type or missing type — convert via content handler
                    flushPending()
                    if item["role"] != nil || item["content"] != nil {
                        let role = responsesRoleToChatRole(item["role"] as? String)
                        let rawContent = item["content"]
                        let chatContent = rawContent.map { responsesContentToChatContent(role, $0) } ?? NSNull()
                        var message: [String: Any] = [
                            "role": role,
                            "content": chatContent
                        ]
                        if role == "assistant" {
                            appendReasoning(&pendingReasoning, responsesItemReasoningText(item))
                            attachPendingReasoning(&message, &pendingReasoning)
                        } else {
                            pendingReasoning = nil
                        }
                        lastAssistantIndex = messages.count
                        messages.append(message)
                    }
                default:
                    // Unknown type — still convert content (cc-switch fallback)
                    flushPending()
                    if item["role"] != nil || item["content"] != nil {
                        let role = responsesRoleToChatRole(item["role"] as? String)
                        let rawContent = item["content"]
                        let chatContent = rawContent.map { responsesContentToChatContent(role, $0) } ?? NSNull()
                        var message: [String: Any] = [
                            "role": role,
                            "content": chatContent
                        ]
                        if role == "assistant" {
                            appendReasoning(&pendingReasoning, responsesItemReasoningText(item))
                            attachPendingReasoning(&message, &pendingReasoning)
                        } else {
                            pendingReasoning = nil
                        }
                        lastAssistantIndex = messages.count
                        messages.append(message)
                    }
                }
            }
        } else if let dict = input as? [String: Any] {
            // Single item
            let itemType = dict["type"] as? String
            if itemType == "input_text" || itemType == "input_image" || itemType == "input_file" || dict["role"] != nil {
                let role = responsesRoleToChatRole(dict["role"] as? String)
                messages.append([
                    "role": role,
                    "content": responsesContentToChatContent(role, [dict])
                ])
            }
        }

        // Flush any remaining pending tool calls
        flushPending()
        // Backfill reasoning placeholders for tool call messages
        backfillToolCallReasoningPlaceholders(&messages)
    }

    // MARK: - Reasoning helpers

    private func appendReasoning(_ pending: inout String?, _ reasoning: String?) {
        guard let r = reasoning?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return }
        if var existing = pending, !existing.isEmpty {
            existing += "\n\n\(r)"
            pending = existing
        } else {
            pending = r
        }
    }

    private func appendUniqueReasoning(_ pending: inout String?, _ reasoning: String?) {
        guard let r = reasoning?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return }
        if var existing = pending {
            if existing.contains(r) { return }
            if !existing.isEmpty { existing += "\n\n" }
            existing += r
            pending = existing
        } else {
            pending = r
        }
    }

    private func attachPendingReasoning(_ message: inout [String: Any], _ pending: inout String?) {
        guard let reasoning = pending, !reasoning.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        pending = nil
        if let existing = message["reasoning_content"] as? String, !existing.isEmpty {
            message["reasoning_content"] = "\(existing)\n\n\(reasoning)"
        } else {
            message["reasoning_content"] = reasoning
        }
    }

    private func attachReasoningToLastAssistant(_ messages: inout [[String: Any]], _ index: Int?, _ reasoning: String?) -> Bool {
        guard let r = reasoning?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return true }
        guard let idx = index, idx < messages.count else { return false }
        guard messages[idx]["role"] as? String == "assistant" else { return false }
        if let existing = messages[idx]["reasoning_content"] as? String, !existing.isEmpty {
            messages[idx]["reasoning_content"] = "\(existing)\n\n\(r)"
        } else {
            messages[idx]["reasoning_content"] = r
        }
        return true
    }

    private func backfillToolCallReasoningPlaceholders(_ messages: inout [[String: Any]]) {
        for i in 0..<messages.count {
            if messages[i]["role"] as? String == "assistant",
               let toolCalls = messages[i]["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                let rc = messages[i]["reasoning_content"] as? String ?? ""
                if rc.trimmingCharacters(in: .whitespaces).isEmpty {
                    messages[i]["reasoning_content"] = "tool call"
                }
            }
        }
    }

    private func responsesItemReasoningText(_ item: [String: Any]) -> String? {
        reasoningRectifier.extractReasoningText(item)
    }

    private func responsesReasoningItemText(_ item: [String: Any]) -> String? {
        // Extract from reasoning summary
        if let summary = item["summary"] as? [[String: Any]] {
            return summary.compactMap { ($0["text"] as? String) ?? ($0["content"] as? String) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }
        return item["reasoning_content"] as? String
            ?? item["content"] as? String
            ?? item["text"] as? String
    }

    // MARK: - Role mapping

    private func responsesRoleToChatRole(_ role: String?) -> String {
        switch role {
        case "system", "developer": return "system"
        case "assistant": return "assistant"
        case "tool": return "tool"
        case "user", "latest_reminder": return "user"
        default: return "user"
        }
    }

    // MARK: - Content conversion

    private func responsesContentToChatContent(_ role: String, _ content: Any) -> Any {
        // cc-switch: if content is null or string, return as-is
        if content is NSNull { return NSNull() }
        if let str = content as? String { return str }

        guard let parts = content as? [[String: Any]] else { return content }
        var chatParts: [[String: Any]] = []
        var hasNonTextPart = false

        for part in parts {
            let partType = part["type"] as? String ?? ""
            switch partType {
            case "input_text", "output_text", "text":
                if let text = part["text"] as? String, !text.isEmpty {
                    chatParts.append(["type": "text", "text": text])
                }
            case "refusal":
                if let text = part["refusal"] as? String, !text.isEmpty {
                    chatParts.append(["type": "text", "text": text])
                }
            case "input_image":
                if let imageUrl = part["image_url"] {
                    let url = imageUrl is [String: Any] ? imageUrl : ["url": imageUrl]
                    chatParts.append(["type": "image_url", "image_url": url])
                    hasNonTextPart = true
                }
            case "input_file":
                var file: [String: Any] = [:]
                let hasRef = part["file_id"] != nil || part["file_data"] != nil
                guard hasRef else { continue }
                for key in ["file_id", "file_data", "filename"] {
                    if let v = part[key] { file[key] = v }
                }
                chatParts.append(["type": "file", "file": file])
                hasNonTextPart = true
            case "input_audio":
                if let audio = part["input_audio"] {
                    chatParts.append(["type": "input_audio", "input_audio": audio])
                    hasNonTextPart = true
                }
            default: break
            }
        }

        if !hasNonTextPart {
            return chatParts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return chatParts
    }

    // MARK: - System message collapsing (MiniMax compat, cc-switch)

    private func collapseSystemMessagesToHead(_ messages: [[String: Any]]) -> [[String: Any]] {
        var systemChunks: [String] = []
        var rest: [[String: Any]] = []

        for msg in messages {
            if msg["role"] as? String == "system",
               let content = msg["content"] as? String {
                let trimmed = content.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { systemChunks.append(content) }
                continue
            }
            rest.append(msg)
        }

        var out: [[String: Any]] = []
        if !systemChunks.isEmpty {
            out.append(["role": "system", "content": systemChunks.joined(separator: "\n\n")])
        }
        out.append(contentsOf: rest)
        return out
    }

    // MARK: - Tool call conversion

    private func responsesFunctionCallToChatToolCall(_ item: [String: Any], toolContext: CodexToolContext) -> [String: Any] {
        let callId = item["call_id"] as? String ?? item["id"] as? String ?? ""
        let name = item["name"] as? String ?? ""
        let namespace = item["namespace"] as? String
        let chatName = toolContext.chatNameForResponseFunction(name: name, namespace: namespace)
        let arguments = canonicalizeToolArguments(item["arguments"] ?? "")

        return [
            "id": callId,
            "type": "function",
            "function": ["name": chatName, "arguments": arguments]
        ]
    }

    private func responsesCustomToolCallToChat(_ item: [String: Any]) -> [String: Any] {
        let callId = item["call_id"] as? String ?? item["id"] as? String ?? ""
        let name = item["name"] as? String ?? ""
        let input = item["input"] ?? ""

        return [
            "id": callId,
            "type": "function",
            "function": [
                "name": name,
                "arguments": canonicalizeJSONString(["input": input])
            ]
        ]
    }

    private func responsesToolSearchCallToChat(_ item: [String: Any]) -> [String: Any] {
        let callId = item["call_id"] as? String ?? item["id"] as? String ?? ""
        let arguments = canonicalizeJSONString(item["arguments"] ?? "")

        return [
            "id": callId,
            "type": "function",
            "function": ["name": "tool_search", "arguments": arguments]
        ]
    }

    private func responsesToolChoiceToChat(_ toolChoice: Any, toolContext: CodexToolContext) -> Any {
        guard let dict = toolChoice as? [String: Any],
              let type = dict["type"] as? String else { return toolChoice }

        switch type {
        case "function":
            let name = dict["name"] as? String ?? ""
            let namespace = dict["namespace"] as? String
            let chatName = toolContext.chatNameForResponseFunction(name: name, namespace: namespace)
            return ["type": "function", "function": ["name": chatName]]
        case "tool_search":
            return ["type": "function", "function": ["name": "tool_search"]]
        case "custom":
            let name = dict["name"] as? String ?? ""
            return ["type": "function", "function": ["name": name]]
        default:
            return toolChoice
        }
    }

    // MARK: - Error normalization (cc-switch chat_error_to_response_error)

    /// Normalize Chat API error to Responses API error format.
    /// cc-switch's chat_error_to_response_error: standard OpenAI, MiniMax base_resp, plain text, detail field.
    private func chatErrorToResponseError(_ value: [String: Any]) -> [String: Any] {
        let errorObj = value["error"] as? [String: Any]
        let source = errorObj ?? value

        // Extract message (cc-switch priority: message → detail → status_msg → base_resp.status_msg → serialize)
        var msg: String?
        if let s = source["message"] as? String { msg = s }
        else if let s = source["detail"] as? String { msg = s }
        else if let s = source["status_msg"] as? String { msg = s }
        else if let s = (source["base_resp"] as? [String: Any])?["status_msg"] as? String { msg = s }
        else if let data = try? JSONSerialization.data(withJSONObject: source),
                let s = String(data: data, encoding: .utf8) { msg = s }
        let message = msg ?? "Upstream error"

        let errorType: String
        if let t = errorObj?["type"] as? String { errorType = t }
        else if let t = source["type"] as? String { errorType = t }
        else { errorType = "upstream_error" }

        let code: Any = errorObj?["code"] ?? source["code"] ?? NSNull()
        let param: Any = errorObj?["param"] ?? source["param"] ?? NSNull()

        return ["error": ["message": message, "type": errorType, "code": code, "param": param]]
    }

    // MARK: - Helpers

    private func isOpenAIOseries(model: String) -> Bool {
        let m = model.lowercased()
        guard m.count > 1, m.hasPrefix("o") else { return false }
        return m[m.index(after: m.startIndex)].isNumber
    }

    private func injectOpenAIStreamIncludeUsage(_ result: inout [String: Any]) {
        guard result["stream"] as? Bool == true else { return }
        var streamOptions = result["stream_options"] as? [String: Any] ?? [:]
        streamOptions["include_usage"] = true
        result["stream_options"] = streamOptions
    }

    private func canonicalizeJSONString(_ value: Any) -> String {
        if let str = value as? String {
            // Try to parse and re-encode for canonical form
            if let data = str.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               let reencoded = try? JSONSerialization.data(withJSONObject: json, options: .sortedKeys),
               let canon = String(data: reencoded, encoding: .utf8) {
                return canon
            }
            return str
        }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private func canonicalizeToolArguments(_ value: Any) -> String {
        if let str = value as? String {
            if let data = str.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               let reencoded = try? JSONSerialization.data(withJSONObject: json, options: .sortedKeys),
               let canon = String(data: reencoded, encoding: .utf8) {
                return canon
            }
            return str
        }
        return canonicalizeJSONString(value)
    }
}
