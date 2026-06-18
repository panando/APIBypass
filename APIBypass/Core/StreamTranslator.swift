import Foundation

// MARK: - SSE Event

struct SSEEvent {
    let event: String?
    let data: String
}

// MARK: - Stream Translator

/// Anthropic ↔ OpenAI 流式 SSE 格式双向转换器
final class StreamTranslator {

    // MARK: - OpenAI → Anthropic

    func translateOpenAIToAnthropic(
        bytes: URLSession.AsyncBytes,
        model: String,
        reqId: String = "none"
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var messageStarted = false
                    var messageId = "msg_apibypass"
                    var inThinkingBlock = false
                    var thinkingBlockIndex = -1
                    var inTextBlock = false
                    var textBlockIndex = -1
                    var toolStates: [Int: (id: String, name: String, args: String, blockIdx: Int)] = [:]
                    var nextBlockIndex = 0
                    var usageChunk: [String: Any]?
                    var finishReason: String?
                    var upstreamChunkIndex = 0
                    var outEventIndex = 0

                    func yieldOut(_ sse: String) {
                        outEventIndex += 1
                        TraceLogger.shared.log(reqId, "out #\(String(format: "%03d", outEventIndex)): \(sse.replacingOccurrences(of: "\n", with: "\\n"))")
                        continuation.yield(sse)
                    }

                    /// Stop current thinking block (if any) and emit content_block_stop
                    func stopThinking() {
                        guard inThinkingBlock else { return }
                        inThinkingBlock = false
                        let stopBlock = anthropicSSE(
                            event: "content_block_stop",
                            data: ["type": "content_block_stop", "index": thinkingBlockIndex]
                        )
                        yieldOut(stopBlock)
                        // Emit signature delta (dummy for non-Anthropic models)
                        let sigEvent = anthropicSSE(
                            event: "content_block_delta",
                            data: ["type": "content_block_delta", "index": thinkingBlockIndex, "delta": ["type": "signature_delta", "signature": "Eq4EAC8KAQw="]]
                        )
                        yieldOut(sigEvent)
                    }

                    /// Stop current text block (if any)
                    func stopText() {
                        guard inTextBlock else { return }
                        inTextBlock = false
                        let stopBlock = anthropicSSE(
                            event: "content_block_stop",
                            data: ["type": "content_block_stop", "index": textBlockIndex]
                        )
                        yieldOut(stopBlock)
                    }

                    /// Stop any active content block
                    func stopActiveBlock() {
                        if inThinkingBlock { stopThinking() }
                        if inTextBlock { stopText() }
                    }

                    for try await event in SSEDecoder.decode(bytes: bytes) {
                        let data = event.data
                        upstreamChunkIndex += 1
                        TraceLogger.shared.log(reqId, "in  #\(String(format: "%03d", upstreamChunkIndex)): \(data.prefix(300))")

                        // Check for [DONE]
                        if data == "[DONE]" {
                            TraceLogger.shared.log(reqId, "in  #\(String(format: "%03d", upstreamChunkIndex)): [DONE] — breaking loop")
                            break
                        }

                        guard let jsonData = data.data(using: .utf8),
                              let chunk = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                            TraceLogger.shared.log(reqId, "in  #\(String(format: "%03d", upstreamChunkIndex)): JSON parse failed, skipping")
                            continue
                        }

                        // Capture usage
                        if let usage = chunk["usage"] as? [String: Any] {
                            usageChunk = usage
                        }

                        guard let choices = chunk["choices"] as? [[String: Any]],
                              let first = choices.first else {
                            TraceLogger.shared.log(reqId, "in  #\(String(format: "%03d", upstreamChunkIndex)): no choices, skipping")
                            continue
                        }

                        let delta = first["delta"] as? [String: Any] ?? [:]

                        // message_start on first chunk
                        if !messageStarted {
                            messageStarted = true
                            if let id = chunk["id"] as? String { messageId = id }
                            let startEvent = anthropicSSE(
                                event: "message_start",
                                data: ["type": "message_start", "message": [
                                    "id": messageId,
                                    "type": "message",
                                    "role": "assistant",
                                    "model": model,
                                    "content": [],
                                    "stop_reason": NSNull(),
                                    "stop_sequence": NSNull(),
                                    "usage": ["input_tokens": 0, "output_tokens": 0]
                                ]]
                            )
                            yieldOut(startEvent)

                            // If the first delta has a role, we can move on
                            _ = delta["role"] as? String
                        }

                        // Reasoning/thinking content (OpenAI format: reasoning_content)
                        if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                            if !inThinkingBlock {
                                stopActiveBlock()
                                inThinkingBlock = true
                                thinkingBlockIndex = nextBlockIndex
                                nextBlockIndex += 1
                                let startBlock = anthropicSSE(
                                    event: "content_block_start",
                                    data: ["type": "content_block_start", "index": thinkingBlockIndex, "content_block": ["type": "thinking", "thinking": ""]]
                                )
                                yieldOut(startBlock)
                            }
                            let deltaEvent = anthropicSSE(
                                event: "content_block_delta",
                                data: ["type": "content_block_delta", "index": thinkingBlockIndex, "delta": ["type": "thinking_delta", "thinking": reasoning]]
                            )
                            yieldOut(deltaEvent)
                        }

                        // Text content
                        if let content = delta["content"] as? String, !content.isEmpty {
                            stopThinking()
                            if !inTextBlock {
                                inTextBlock = true
                                textBlockIndex = nextBlockIndex
                                nextBlockIndex += 1
                                let startBlock = anthropicSSE(
                                    event: "content_block_start",
                                    data: ["type": "content_block_start", "index": textBlockIndex, "content_block": ["type": "text", "text": ""]]
                                )
                                yieldOut(startBlock)
                            }
                            let deltaEvent = anthropicSSE(
                                event: "content_block_delta",
                                data: ["type": "content_block_delta", "index": textBlockIndex, "delta": ["type": "text_delta", "text": content]]
                            )
                            yieldOut(deltaEvent)
                        }

                        // Tool calls
                        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                            for tc in toolCalls {
                                let index = tc["index"] as? Int ?? 0
                                let id = tc["id"] as? String
                                let funcInfo = tc["function"] as? [String: Any]
                                let name = funcInfo?["name"] as? String
                                let arguments = funcInfo?["arguments"] as? String ?? ""

                                if let id = id, toolStates[index] == nil {
                                    // New tool call
                                    stopActiveBlock()
                                    let blockIdx = nextBlockIndex
                                    nextBlockIndex += 1
                                    toolStates[index] = (id: id, name: name ?? "", args: "", blockIdx: blockIdx)
                                    let startTool = anthropicSSE(
                                        event: "content_block_start",
                                        data: ["type": "content_block_start", "index": blockIdx, "content_block": ["type": "tool_use", "id": id, "name": name ?? "", "input": [:]]]
                                    )
                                    yieldOut(startTool)
                                }

                                if var state = toolStates[index] {
                                    if let id = id { state.id = id; toolStates[index] = state }
                                    if let name = name { state.name = name; toolStates[index] = state }
                                    if !arguments.isEmpty {
                                        state.args += arguments
                                        toolStates[index] = state
                                        let deltaTool = anthropicSSE(
                                            event: "content_block_delta",
                                            data: ["type": "content_block_delta", "index": state.blockIdx, "delta": ["type": "input_json_delta", "partial_json": arguments]]
                                        )
                                        yieldOut(deltaTool)
                                    }
                                }
                            }
                        }

                        // Finish reason
                        if let fr = first["finish_reason"] as? String, !fr.isEmpty {
                            finishReason = fr
                        }
                    }

                    TraceLogger.shared.log(reqId, "━━━ upstream loop ended: \(upstreamChunkIndex) chunks received ━━━")

                    // Close blocks
                    stopActiveBlock()
                    let sortedToolIndices = toolStates.keys.sorted()
                    for idx in sortedToolIndices {
                        // Emit stop for each tool block using the stored block index
                        guard let state = toolStates[idx] else { continue }
                        let stopTool = anthropicSSE(
                            event: "content_block_stop",
                            data: ["type": "content_block_stop", "index": state.blockIdx]
                        )
                        yieldOut(stopTool)
                    }

                    // message_delta
                    let sr = finishReason.map { mapOAIFinishReason($0) } ?? "end_turn"
                    var deltaData: [String: Any] = [
                        "type": "message_delta",
                        "delta": ["stop_reason": sr, "stop_sequence": NSNull()]
                    ]
                    if let usage = usageChunk {
                        deltaData["usage"] = mapOAIStreamUsageToAnthropic(usage)
                    } else {
                        deltaData["usage"] = ["output_tokens": 0]
                    }
                    yieldOut(anthropicSSE(event: "message_delta", data: deltaData))

                    // message_stop
                    yieldOut(anthropicSSE(event: "message_stop", data: ["type": "message_stop"]))

                    TraceLogger.shared.log(reqId, "━━━ translated stream finished: \(outEventIndex) events sent ━━━")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Anthropic → OpenAI

    func translateAnthropicToOpenAI(
        bytes: URLSession.AsyncBytes,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var chunkId = "chatcmpl_apibypass"
                    let created = Int(Date().timeIntervalSince1970)

                    for try await event in SSEDecoder.decode(bytes: bytes) {
                        guard let jsonData = event.data.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                            continue
                        }

                        let type = obj["type"] as? String ?? ""

                        switch type {
                        case "message_start":
                            if let msg = obj["message"] as? [String: Any],
                               let id = msg["id"] as? String {
                                chunkId = id
                            }
                            // Emit initial chunk with role
                            let chunk = oaiChunk(id: chunkId, model: model, created: created,
                                                 delta: ["role": "assistant"])
                            print("[SSEConverter] message_start -> OpenAI chunk")
                            continuation.yield(chunk)

                        case "content_block_start":
                            let block = obj["content_block"] as? [String: Any] ?? [:]
                            let blockType = block["type"] as? String ?? ""
                            if blockType == "tool_use" {
                                let id = block["id"] as? String ?? ""
                                let name = block["name"] as? String ?? ""
                                let chunk = oaiChunk(id: chunkId, model: model, created: created,
                                    delta: ["tool_calls": [[
                                        "index": obj["index"] ?? 0,
                                        "id": id,
                                        "type": "function",
                                        "function": ["name": name, "arguments": ""]
                                    ]]])
                                continuation.yield(chunk)
                            } else if blockType == "redacted_thinking" {
                                    let chunk = oaiChunk(id: chunkId, model: model, created: created,
                                                         delta: ["reasoning_content": "(推理内容已隐藏)"])
                                    continuation.yield(chunk)
                                }

                        case "content_block_delta":
                            let delta = obj["delta"] as? [String: Any] ?? [:]
                            switch delta["type"] as? String {
                            case "text_delta":
                                if let text = delta["text"] as? String {
                                    print("[SSEConverter] text_delta: \(text.prefix(50))")
                                    let chunk = oaiChunk(id: chunkId, model: model, created: created,
                                                         delta: ["content": text])
                                    continuation.yield(chunk)
                                }
                            case "thinking_delta":
                                if let thinking = delta["thinking"] as? String {
                                    let chunk = oaiChunk(id: chunkId, model: model, created: created,
                                                         delta: ["reasoning_content": thinking])
                                    continuation.yield(chunk)
                                }
                            case "signature_delta":
                                // signature 仅在多轮对话中需要传递，此处忽略
                                break
                            case "input_json_delta":
                                if let json = delta["partial_json"] as? String {
                                    let chunk = oaiChunk(id: chunkId, model: model, created: created,
                                        delta: ["tool_calls": [[
                                            "index": obj["index"] ?? 0,
                                            "function": ["arguments": json]
                                        ]]])
                                    continuation.yield(chunk)
                                }
                            default:
                                break
                            }

                        case "content_block_stop":
                            break

                        case "message_delta":
                            let d = obj["delta"] as? [String: Any] ?? [:]
                            let stopReason = d["stop_reason"] as? String ?? "end_turn"
                            let finishReason = mapAnthropicStopReason(stopReason)
                            var delta: [String: Any] = [:]
                            if finishReason == "tool_calls" {
                                delta = ["tool_calls": [[String: Any]]()] // empty to trigger finish
                            }
                            var chunkObj: [String: Any] = [
                                "id": chunkId,
                                "object": "chat.completion.chunk",
                                "created": created,
                                "model": model,
                                "choices": [[
                                    "index": 0,
                                    "delta": delta,
                                    "finish_reason": finishReason
                                ]]
                            ]
                            if let usage = obj["usage"] as? [String: Any] {
                                chunkObj["usage"] = mapAnthropicStreamUsageToOAI(usage)
                            }
                            continuation.yield(oaiSSE(data: chunkObj))

                        case "message_stop":
                            print("[SSEConverter] message_stop -> [DONE]")
                            continuation.yield("data: [DONE]\n\n")

                        default:
                            break
                        }
                    }

                    print("[SSEConverter] 流处理完成")
                    continuation.finish()
                } catch {
                    print("[SSEConverter] 流处理错误: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - SSE formatting helpers

    private func anthropicSSE(event: String, data: [String: Any]) -> String {
        let dataStr = (try? JSONSerialization.data(withJSONObject: data))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "event: \(event)\ndata: \(dataStr)\n\n"
    }

    private func oaiChunk(id: String, model: String, created: Int, delta: [String: Any]) -> String {
        let obj: [String: Any] = [
            "id": id,
            "object": "chat.completion.chunk",
            "created": created,
            "model": model,
            "choices": [[
                "index": 0,
                "delta": delta,
                "finish_reason": NSNull()
            ]]
        ]
        return oaiSSE(data: obj)
    }

    private func oaiSSE(data: [String: Any]) -> String {
        let dataStr = (try? JSONSerialization.data(withJSONObject: data))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "data: \(dataStr)\n\n"
    }

    // MARK: - Usage mapping

    private func mapOAIStreamUsageToAnthropic(_ usage: [String: Any]) -> [String: Any] {
        let input = usage["prompt_tokens"] as? Int ?? 0
        let output = usage["completion_tokens"] as? Int ?? 0
        var out: [String: Any] = ["input_tokens": input, "output_tokens": output]
        if let details = usage["prompt_tokens_details"] as? [String: Any],
           let cached = details["cached_tokens"] as? Int {
            out["cache_read_input_tokens"] = cached
        }
        return out
    }

    private func mapAnthropicStreamUsageToOAI(_ usage: [String: Any]) -> [String: Any] {
        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        return ["prompt_tokens": input, "completion_tokens": output, "total_tokens": input + output]
    }

    private func mapOAIFinishReason(_ reason: String) -> String {
        switch reason {
        case "stop":        return "end_turn"
        case "length":      return "max_tokens"
        case "tool_calls":  return "tool_use"
        default:            return "end_turn"
        }
    }

    private func mapAnthropicStopReason(_ reason: String) -> String {
        switch reason {
        case "end_turn":   return "stop"
        case "tool_use":   return "tool_calls"
        case "max_tokens": return "length"
        default:           return "stop"
        }
    }
}

// MARK: - SSE Decoder

private enum SSEDecoder {
    static func decode(bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    print("[SSEDecoder] 开始解码 SSE 流...")
                    var currentEvent: String?
                    var eventCount = 0

                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .newlines)
                        // Trim trailing \r
                        let clean = trimmed.hasSuffix("\r") ? String(trimmed.dropLast()) : trimmed

                        if clean.isEmpty {
                            // Empty line = event boundary (标准 SSE 格式)
                            currentEvent = nil
                            continue
                        }

                        if clean.hasPrefix("event:") {
                            currentEvent = String(clean.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if clean.hasPrefix("data:") {
                            // 收到 data 行后立即 yield 事件（不等待空行）
                            let data = String(clean.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            eventCount += 1
                            print("[SSEDecoder] 事件 #\(eventCount): event=\(currentEvent ?? "nil"), data=\(data.prefix(100))")
                            continuation.yield(SSEEvent(event: currentEvent, data: data))
                            // 重置 event 类型，但不需要等待空行
                            currentEvent = nil
                        }
                    }

                    print("[SSEDecoder] 流结束，共解码 \(eventCount) 个事件")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
