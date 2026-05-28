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
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var messageStarted = false
                    var messageId = "msg_apibypass"
                    var inTextBlock = false
                    var textBlockIndex = -1
                    var toolStates: [Int: (id: String, name: String, args: String)] = [:]
                    var nextBlockIndex = 0
                    var usageChunk: [String: Any]?
                    var finishReason: String?

                    for try await event in SSEDecoder.decode(bytes: bytes) {
                        let data = event.data

                        // Check for [DONE]
                        if data == "[DONE]" { break }

                        guard let jsonData = data.data(using: .utf8),
                              let chunk = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                            continue
                        }

                        // Capture usage
                        if let usage = chunk["usage"] as? [String: Any] {
                            usageChunk = usage
                        }

                        guard let choices = chunk["choices"] as? [[String: Any]],
                              let first = choices.first else {
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
                            continuation.yield(startEvent)

                            // If the first delta has a role, we can move on
                            _ = delta["role"] as? String
                        }

                        // Text content
                        if let content = delta["content"] as? String, !content.isEmpty {
                            if !inTextBlock {
                                inTextBlock = true
                                textBlockIndex = nextBlockIndex
                                nextBlockIndex += 1
                                let startBlock = anthropicSSE(
                                    event: "content_block_start",
                                    data: ["type": "content_block_start", "index": textBlockIndex, "content_block": ["type": "text", "text": ""]]
                                )
                                continuation.yield(startBlock)
                            }
                            let deltaEvent = anthropicSSE(
                                event: "content_block_delta",
                                data: ["type": "content_block_delta", "index": textBlockIndex, "delta": ["type": "text_delta", "text": content]]
                            )
                            continuation.yield(deltaEvent)
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
                                    if inTextBlock {
                                        inTextBlock = false
                                        let stopBlock = anthropicSSE(
                                            event: "content_block_stop",
                                            data: ["type": "content_block_stop", "index": textBlockIndex]
                                        )
                                        continuation.yield(stopBlock)
                                    }
                                    let blockIdx = nextBlockIndex
                                    nextBlockIndex += 1
                                    toolStates[index] = (id: id, name: name ?? "", args: "")
                                    let startTool = anthropicSSE(
                                        event: "content_block_start",
                                        data: ["type": "content_block_start", "index": blockIdx, "content_block": ["type": "tool_use", "id": id, "name": name ?? "", "input": [:]]]
                                    )
                                    continuation.yield(startTool)
                                }

                                if var state = toolStates[index] {
                                    if let id = id { state.id = id; toolStates[index] = state }
                                    if let name = name { state.name = name; toolStates[index] = state }
                                    if !arguments.isEmpty {
                                        state.args += arguments
                                        toolStates[index] = state
                                        let blockIdx = nextBlockIndex - 1
                                        let deltaTool = anthropicSSE(
                                            event: "content_block_delta",
                                            data: ["type": "content_block_delta", "index": blockIdx, "delta": ["type": "input_json_delta", "partial_json": arguments]]
                                        )
                                        continuation.yield(deltaTool)
                                    }
                                }
                            }
                        }

                        // Finish reason
                        if let fr = first["finish_reason"] as? String, !fr.isEmpty {
                            finishReason = fr
                        }
                    }

                    // Close blocks
                    if inTextBlock {
                        let stopBlock = anthropicSSE(
                            event: "content_block_stop",
                            data: ["type": "content_block_stop", "index": textBlockIndex]
                        )
                        continuation.yield(stopBlock)
                    }
                    let sortedToolIndices = toolStates.keys.sorted()
                    for idx in sortedToolIndices {
                        // Emit stop for each tool block
                        // Find the block index by ordering
                        let blockIdx = idx  // approximate
                        let stopTool = anthropicSSE(
                            event: "content_block_stop",
                            data: ["type": "content_block_stop", "index": blockIdx]
                        )
                        continuation.yield(stopTool)
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
                    continuation.yield(anthropicSSE(event: "message_delta", data: deltaData))

                    // message_stop
                    continuation.yield(anthropicSSE(event: "message_stop", data: ["type": "message_stop"]))

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
                            }

                        case "content_block_delta":
                            let delta = obj["delta"] as? [String: Any] ?? [:]
                            switch delta["type"] as? String {
                            case "text_delta":
                                if let text = delta["text"] as? String {
                                    let chunk = oaiChunk(id: chunkId, model: model, created: created,
                                                         delta: ["content": text])
                                    continuation.yield(chunk)
                                }
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
                            continuation.yield("data: [DONE]\n\n")

                        default:
                            break
                        }
                    }

                    continuation.finish()
                } catch {
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
                    var currentEvent: String?
                    var dataLines: [String] = []

                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .newlines)
                        // Trim trailing \r
                        let clean = trimmed.hasSuffix("\r") ? String(trimmed.dropLast()) : trimmed

                        if clean.isEmpty {
                            // Empty line = event boundary
                            if !dataLines.isEmpty {
                                let data = dataLines.joined(separator: "\n")
                                continuation.yield(SSEEvent(event: currentEvent, data: data))
                            }
                            currentEvent = nil
                            dataLines = []
                            continue
                        }

                        if clean.hasPrefix("event:") {
                            currentEvent = String(clean.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if clean.hasPrefix("data:") {
                            dataLines.append(String(clean.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                    }

                    // Flush remaining
                    if !dataLines.isEmpty {
                        continuation.yield(SSEEvent(event: currentEvent, data: dataLines.joined(separator: "\n")))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
