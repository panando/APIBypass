import Foundation
import NIOCore

// MARK: - SSE Parser

/// Parses Server-Sent Events from a byte stream.
public struct SSEParser: Sendable {
    public init() {}

    public func parse(_ data: Data) -> [SSEEvent] {
        guard let string = String(data: data, encoding: .utf8) else { return [] }
        var events: [SSEEvent] = []
        var currentId: String?
        var currentEvent: String?
        var currentData = ""

        for line in string.components(separatedBy: .newlines) {
            let trimmed = line.hasSuffix("\r") ? String(line.dropLast()) : line
            if trimmed.isEmpty {
                if !currentData.isEmpty {
                    events.append(SSEEvent(id: currentId, event: currentEvent, data: currentData))
                }
                currentId = nil
                currentEvent = nil
                currentData = ""
            } else if trimmed.hasPrefix("id:") {
                currentId = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("event:") {
                currentEvent = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("data:") {
                let value = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                currentData = currentData.isEmpty ? value : currentData + "\n" + value
            }
        }

        if !currentData.isEmpty {
            events.append(SSEEvent(id: currentId, event: currentEvent, data: currentData))
        }
        return events
    }
}

/// SSE event structure.
public struct SSEEvent: Sendable {
    public var id: String?
    public var event: String?
    public var data: String

    public init(id: String? = nil, event: String? = nil, data: String) {
        self.id = id
        self.event = event
        self.data = data
    }
}

// MARK: - Inline think state

private enum InlineThinkMode {
    case detecting
    case reasoning
    case text
}

// MARK: - Tool call state

private struct ToolCallState {
    var outputIndex: Int = 0
    var itemId: String = ""
    var callId: String = ""
    var name: String = ""
    var arguments: String = ""
    var reasoningContent: String = ""
    var added: Bool = false
    var done: Bool = false
}

// MARK: - Main state

/// Streaming state for Chat Completions → Responses SSE conversion.
/// Follows cc-switch's ChatToResponsesState in streaming_codex_chat.rs.
private struct StreamState {
    var responseStarted = false
    var completed = false
    var responseId = "resp_codexrouter"
    var model = ""
    var createdAt: Int = 0
    var nextOutputIndex = 0

    // Text item
    var textOutputIndex: Int = 0
    var textItemId = ""
    var accumulatedText = ""
    var textAdded = false
    var textDone = false

    // Reasoning item
    var reasoningOutputIndex: Int = 0
    var reasoningItemId = ""
    var accumulatedReasoning = ""
    var reasoningAdded = false
    var reasoningDone = false

    // Inline think detection
    var inlineThinkMode = InlineThinkMode.detecting
    var inlineThinkBuffer = ""

    // Tool calls
    var tools: [Int: ToolCallState] = [:]

    // Completed output items (outputIndex, item JSON)
    var outputItems: [(Int, [String: Any])] = []

    // Usage + finish
    var latestUsage: [String: Any]?
    var finishReason: String?

    // Tool context for name restoration
    var toolContext: CodexToolContext
}

// MARK: - Transformer

/// Stateful stream transformer for Chat Completions SSE → Responses API SSE.
/// Follows cc-switch's streaming_codex_chat.rs exactly.
public actor ChatToResponsesStreamTransformer {
    private var state: StreamState
    private let parser = SSEParser()
    private let rectifier = ReasoningRectifier()

    public init(toolContext: CodexToolContext = CodexToolContext()) {
        self.state = StreamState(toolContext: toolContext)
    }

    /// Signal end of upstream stream. Emits final completion or error events.
    public func finish() -> Data? {
        guard !state.completed else { return nil }
        var events: [String] = []
        events.append(contentsOf: ensureResponseStarted())
        events.append(contentsOf: flushInlineThinkAtBoundary())
        events.append(contentsOf: finalizeReasoning())
        events.append(contentsOf: finalizeText())
        events.append(contentsOf: finalizeTools())

        if state.finishReason != nil || hasSubstantiveOutput() {
            // Stream ended with output — complete
            if state.finishReason == nil {
                state.finishReason = "length"
            }
            let status = responseStatusFromFinishReason(state.finishReason)
            events.append(createResponseCompletedEvent(status: status))
            state.completed = true
        } else {
            // Stream ended without any output — failed
            events.append(createResponseFailedEvent(
                message: "Upstream Chat Completions stream ended before sending finish_reason",
                code: "stream_truncated"
            ))
            state.completed = true
        }

        guard !events.isEmpty else { return nil }
        return events.joined().data(using: .utf8)
    }

    /// Transform incoming SSE data. Returns transformed SSE text to forward to Codex.
    public func transform(_ data: Data) -> Data? {
        let parsedEvents = parser.parse(data)
        var outputEvents: [String] = []

        for event in parsedEvents {
            guard !event.data.isEmpty else { continue }

            if event.data.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                // [DONE] from upstream — finalize
                outputEvents.append(contentsOf: ensureResponseStarted())
                outputEvents.append(contentsOf: flushInlineThinkAtBoundary())
                outputEvents.append(contentsOf: finalizeReasoning())
                outputEvents.append(contentsOf: finalizeText())
                outputEvents.append(contentsOf: finalizeTools())
                if !state.completed {
                    let status = responseStatusFromFinishReason(state.finishReason)
                    outputEvents.append(createResponseCompletedEvent(status: status))
                    state.completed = true
                }
                continue
            }

            guard let jsonData = event.data.data(using: .utf8),
                  let chunk = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { continue }

            // Check for error in SSE
            if event.event == "error" || chunk["error"] != nil {
                outputEvents.append(contentsOf: ensureResponseStarted())
                let (message, errorType) = extractChatSSEError(chunk)
                outputEvents.append(createResponseFailedEvent(message: message, code: errorType))
                state.completed = true
                break
            }

            outputEvents.append(contentsOf: handleChatChunk(chunk))
        }

        guard !outputEvents.isEmpty else { return nil }
        return outputEvents.joined().data(using: .utf8)
    }

    // MARK: - Chunk handling

    private func handleChatChunk(_ chunk: [String: Any]) -> [String] {
        var events: [String] = []

        if let id = chunk["id"] as? String { state.responseId = "resp_\(id)" }
        if let model = chunk["model"] as? String, !model.isEmpty { state.model = model }
        if let created = chunk["created"] as? Int { state.createdAt = created }

        events.append(contentsOf: ensureResponseStarted())

        if let usage = chunk["usage"] as? [String: Any] {
            state.latestUsage = convertUsage(usage)
        }

        guard let choices = chunk["choices"] as? [[String: Any]],
              let choice = choices.first else { return events }

        // Process delta
        if let delta = choice["delta"] as? [String: Any] {
            // Reasoning delta
            if let reasoning = extractReasoning(delta), !reasoning.isEmpty {
                events.append(contentsOf: pushReasoningDelta(reasoning))
                appendReasoningToActiveTools(reasoning)
            }

            // Content delta (with inline think detection)
            if let content = delta["content"] as? String, !content.isEmpty {
                events.append(contentsOf: pushContentDelta(content))
            }

            // Tool calls delta
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                events.append(contentsOf: flushInlineThinkAtBoundary())
                let reasoningForTools = currentReasoningText()
                events.append(contentsOf: finalizeReasoning())
                for toolCall in toolCalls {
                    events.append(contentsOf: pushToolCallDelta(toolCall, reasoning: reasoningForTools))
                }
            }
        }

        if let finishReason = choice["finish_reason"] as? String {
            state.finishReason = finishReason
        }

        return events
    }

    // MARK: - Reasoning delta

    private func pushReasoningDelta(_ delta: String) -> [String] {
        var events: [String] = []

        if !state.reasoningAdded {
            let outputIndex = nextOutputIndex()
            let itemId = "rs_\(state.responseId)"
            state.reasoningOutputIndex = outputIndex
            state.reasoningItemId = itemId
            state.reasoningAdded = true

            events.append(sseEvent("response.output_item.added", [
                "type": "response.output_item.added",
                "output_index": outputIndex,
                "item": [
                    "id": itemId,
                    "type": "reasoning",
                    "status": "in_progress",
                    "summary": [] as [Any]
                ]
            ]))
            events.append(sseEvent("response.reasoning_summary_part.added", [
                "type": "response.reasoning_summary_part.added",
                "item_id": itemId,
                "output_index": outputIndex,
                "summary_index": 0,
                "part": ["type": "summary_text", "text": ""]
            ]))
        }

        state.accumulatedReasoning += delta
        let outputIndex = state.reasoningOutputIndex
        events.append(sseEvent("response.reasoning_summary_text.delta", [
            "type": "response.reasoning_summary_text.delta",
            "item_id": state.reasoningItemId,
            "output_index": outputIndex,
            "summary_index": 0,
            "delta": delta
        ]))

        return events
    }

    // MARK: - Content delta with inline think detection

    private func pushContentDelta(_ delta: String) -> [String] {
        switch state.inlineThinkMode {
        case .text:
            var events = finalizeReasoning()
            events.append(contentsOf: pushTextDelta(delta))
            return events

        case .detecting:
            state.inlineThinkBuffer += delta
            switch leadingThinkPrefixDecision(state.inlineThinkBuffer) {
            case .needMore:
                return []
            case .reasoning:
                state.inlineThinkMode = .reasoning
                return drainCompleteInlineThink()
            case .text:
                state.inlineThinkMode = .text
                let text = state.inlineThinkBuffer
                state.inlineThinkBuffer = ""
                var events = finalizeReasoning()
                events.append(contentsOf: pushTextDelta(text))
                return events
            }

        case .reasoning:
            state.inlineThinkBuffer += delta
            return drainCompleteInlineThink()
        }
    }

    private func drainCompleteInlineThink() -> [String] {
        guard let (reasoning, answer) = splitLeadingThinkBlock(state.inlineThinkBuffer) else {
            return []
        }
        state.inlineThinkMode = .text
        state.inlineThinkBuffer = ""

        var events: [String] = []
        if !reasoning.isEmpty {
            events.append(contentsOf: pushReasoningDelta(reasoning))
            events.append(contentsOf: finalizeReasoning())
        }
        if !answer.isEmpty {
            events.append(contentsOf: pushTextDelta(answer))
        }
        return events
    }

    private func flushInlineThinkAtBoundary() -> [String] {
        switch state.inlineThinkMode {
        case .text:
            return []
        case .detecting:
            state.inlineThinkMode = .text
            let text = state.inlineThinkBuffer
            state.inlineThinkBuffer = ""
            if text.isEmpty { return [] }
            var events = finalizeReasoning()
            events.append(contentsOf: pushTextDelta(text))
            return events
        case .reasoning:
            let buffered = state.inlineThinkBuffer
            state.inlineThinkMode = .text
            state.inlineThinkBuffer = ""

            if let (reasoning, answer) = splitLeadingThinkBlock(buffered) {
                var events: [String] = []
                if !reasoning.isEmpty {
                    events.append(contentsOf: pushReasoningDelta(reasoning))
                    events.append(contentsOf: finalizeReasoning())
                }
                if !answer.isEmpty {
                    events.append(contentsOf: pushTextDelta(answer))
                }
                return events
            }

            let reasoning = stripLeadingThinkOpenTag(buffered) ?? buffered
            if reasoning.isEmpty { return [] }
            var events = pushReasoningDelta(reasoning)
            events.append(contentsOf: finalizeReasoning())
            return events
        }
    }

    // MARK: - Text delta

    private func pushTextDelta(_ delta: String) -> [String] {
        var events: [String] = []

        if !state.textAdded {
            let outputIndex = nextOutputIndex()
            let itemId = "\(state.responseId)_msg"
            state.textOutputIndex = outputIndex
            state.textItemId = itemId
            state.textAdded = true

            events.append(sseEvent("response.output_item.added", [
                "type": "response.output_item.added",
                "output_index": outputIndex,
                "item": [
                    "id": itemId,
                    "type": "message",
                    "status": "in_progress",
                    "role": "assistant",
                    "content": [] as [Any]
                ]
            ]))
            events.append(sseEvent("response.content_part.added", [
                "type": "response.content_part.added",
                "item_id": itemId,
                "output_index": outputIndex,
                "content_index": 0,
                "part": ["type": "output_text", "text": "", "annotations": []]
            ]))
        }

        state.accumulatedText += delta
        let outputIndex = state.textOutputIndex
        events.append(sseEvent("response.output_text.delta", [
            "type": "response.output_text.delta",
            "item_id": state.textItemId,
            "output_index": outputIndex,
            "content_index": 0,
            "delta": delta
        ]))

        return events
    }

    // MARK: - Tool call delta

    private func pushToolCallDelta(_ toolCall: [String: Any], reasoning: String?) -> [String] {
        let chatIndex = toolCall["index"] as? Int ?? 0
        let idDelta = toolCall["id"] as? String
        let function = toolCall["function"] as? [String: Any] ?? [:]
        let nameDelta = function["name"] as? String
        let argsDelta = function["arguments"] as? String ?? ""

        var state_ = state.tools[chatIndex] ?? ToolCallState()

        if let id = idDelta { state_.callId = id }
        if let name = nameDelta { state_.name = name }
        if !argsDelta.isEmpty { state_.arguments += argsDelta }
        if state_.reasoningContent.isEmpty, let r = reasoning?.trimmingCharacters(in: .whitespaces), !r.isEmpty {
            state_.reasoningContent = r
        }

        var events: [String] = []
        var shouldAdd = false
        var pendingArgs = ""

        if !state_.added && (!state_.callId.isEmpty || !state_.name.isEmpty) {
            shouldAdd = true
            pendingArgs = state_.arguments
        }

        let isCustomTool = state.toolContext.isCustomToolChatName(state_.name)

        if shouldAdd {
            let assigned = nextOutputIndex()
            state_.added = true
            if state_.callId.isEmpty { state_.callId = "call_\(chatIndex)" }
            if state_.name.isEmpty { state_.name = "unknown_tool" }
            state_.outputIndex = assigned
            state_.itemId = responseToolCallItemId(callId: state_.callId, chatName: state_.name)

            let item = responseToolCallItem(
                itemId: state_.itemId,
                status: "in_progress",
                callId: state_.callId,
                chatName: state_.name,
                arguments: "",
                reasoning: state_.reasoningContent
            )

            events.append(sseEvent("response.output_item.added", [
                "type": "response.output_item.added",
                "output_index": assigned,
                "item": item
            ]))

            if !pendingArgs.isEmpty && !isCustomTool {
                events.append(sseEvent("response.function_call_arguments.delta", [
                    "type": "response.function_call_arguments.delta",
                    "item_id": state_.itemId,
                    "output_index": assigned,
                    "delta": pendingArgs
                ]))
            }
        } else if !argsDelta.isEmpty && !isCustomTool {
            events.append(sseEvent("response.function_call_arguments.delta", [
                "type": "response.function_call_arguments.delta",
                "item_id": state_.itemId,
                "output_index": state_.outputIndex,
                "delta": argsDelta
            ]))
        }

        state.tools[chatIndex] = state_
        return events
    }

    private func appendReasoningToActiveTools(_ delta: String) {
        let delta = delta.trimmingCharacters(in: .whitespaces)
        guard !delta.isEmpty else { return }
        for key in state.tools.keys {
            var ts = state.tools[key]!
            if !ts.done {
                if ts.reasoningContent.isEmpty {
                    ts.reasoningContent = delta
                } else {
                    ts.reasoningContent += delta
                }
                state.tools[key] = ts
            }
        }
    }

    private func currentReasoningText() -> String? {
        let text = state.accumulatedReasoning.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    // MARK: - Finalization

    private func finalizeReasoning() -> [String] {
        guard state.reasoningAdded, !state.reasoningDone else { return [] }

        let outputIndex = state.reasoningOutputIndex
        let itemId = state.reasoningItemId
        let text = state.accumulatedReasoning

        let item: [String: Any] = [
            "id": itemId,
            "type": "reasoning",
            "summary": [["type": "summary_text", "text": text]]
        ]
        state.outputItems.append((outputIndex, item))
        state.reasoningDone = true

        return [
            sseEvent("response.reasoning_summary_text.done", [
                "type": "response.reasoning_summary_text.done",
                "item_id": itemId,
                "output_index": outputIndex,
                "summary_index": 0,
                "text": text
            ]),
            sseEvent("response.reasoning_summary_part.done", [
                "type": "response.reasoning_summary_part.done",
                "item_id": itemId,
                "output_index": outputIndex,
                "summary_index": 0,
                "part": ["type": "summary_text", "text": text]
            ]),
            sseEvent("response.output_item.done", [
                "type": "response.output_item.done",
                "output_index": outputIndex,
                "item": item
            ])
        ]
    }

    private func finalizeText() -> [String] {
        guard state.textAdded, !state.textDone else { return [] }

        let outputIndex = state.textOutputIndex
        let itemId = state.textItemId
        let text = state.accumulatedText

        let item: [String: Any] = [
            "id": itemId,
            "type": "message",
            "status": "completed",
            "role": "assistant",
            "content": [["type": "output_text", "text": text, "annotations": []]]
        ]
        state.outputItems.append((outputIndex, item))
        state.textDone = true

        return [
            sseEvent("response.output_text.done", [
                "type": "response.output_text.done",
                "item_id": itemId,
                "output_index": outputIndex,
                "content_index": 0,
                "text": text
            ]),
            sseEvent("response.content_part.done", [
                "type": "response.content_part.done",
                "item_id": itemId,
                "output_index": outputIndex,
                "content_index": 0,
                "part": ["type": "output_text", "text": text, "annotations": []]
            ]),
            sseEvent("response.output_item.done", [
                "type": "response.output_item.done",
                "output_index": outputIndex,
                "item": item
            ])
        ]
    }

    private func finalizeTools() -> [String] {
        var events: [String] = []
        let keys = state.tools.keys.sorted()

        for key in keys {
            guard var ts = state.tools[key], !ts.done else { continue }

            // If not added yet, add now (finalize)
            if !ts.added {
                ts.added = true
                if ts.callId.isEmpty { ts.callId = "call_\(key)" }
                if ts.name.isEmpty { ts.name = "unknown_tool" }
                ts.outputIndex = nextOutputIndex()
                ts.itemId = responseToolCallItemId(callId: ts.callId, chatName: ts.name)

                let item = responseToolCallItem(
                    itemId: ts.itemId,
                    status: "in_progress",
                    callId: ts.callId,
                    chatName: ts.name,
                    arguments: "",
                    reasoning: ts.reasoningContent
                )
                events.append(sseEvent("response.output_item.added", [
                    "type": "response.output_item.added",
                    "output_index": ts.outputIndex,
                    "item": item
                ]))
            }

            let outputIndex = ts.outputIndex
            let isCustomTool = state.toolContext.isCustomToolChatName(ts.name)
            let arguments = canonicalizeToolArguments(ts.arguments)
            let item = responseToolCallItem(
                itemId: ts.itemId,
                status: "completed",
                callId: ts.callId,
                chatName: ts.name,
                arguments: arguments,
                reasoning: ts.reasoningContent
            )
            ts.done = true
            state.tools[key] = ts
            state.outputItems.append((outputIndex, item))

            if isCustomTool {
                let input = customToolInputFromChatArguments(arguments)
                if !input.isEmpty {
                    events.append(sseEvent("response.custom_tool_call_input.delta", [
                        "type": "response.custom_tool_call_input.delta",
                        "item_id": ts.itemId,
                        "output_index": outputIndex,
                        "delta": input
                    ]))
                }
                events.append(sseEvent("response.custom_tool_call_input.done", [
                    "type": "response.custom_tool_call_input.done",
                    "item_id": ts.itemId,
                    "output_index": outputIndex,
                    "input": input
                ]))
            } else {
                events.append(sseEvent("response.function_call_arguments.done", [
                    "type": "response.function_call_arguments.done",
                    "item_id": ts.itemId,
                    "output_index": outputIndex,
                    "arguments": arguments
                ]))
            }
            events.append(sseEvent("response.output_item.done", [
                "type": "response.output_item.done",
                "output_index": outputIndex,
                "item": item
            ]))
        }

        return events
    }

    private func hasSubstantiveOutput() -> Bool {
        !state.accumulatedText.trimmingCharacters(in: .whitespaces).isEmpty
            || !state.accumulatedReasoning.trimmingCharacters(in: .whitespaces).isEmpty
            || !state.inlineThinkBuffer.trimmingCharacters(in: .whitespaces).isEmpty
            || !state.outputItems.isEmpty
            || state.tools.values.contains(where: { ts in
                ts.added || !ts.callId.trimmingCharacters(in: .whitespaces).isEmpty
                    || !ts.name.trimmingCharacters(in: .whitespaces).isEmpty
                    || !ts.arguments.trimmingCharacters(in: .whitespaces).isEmpty
                    || !ts.reasoningContent.trimmingCharacters(in: .whitespaces).isEmpty
            })
    }

    // MARK: - Event builders

    private func ensureResponseStarted() -> [String] {
        guard !state.responseStarted else { return [] }
        state.responseStarted = true
        let response = baseResponse(status: "in_progress", output: [])
        return [
            sseEvent("response.created", ["type": "response.created", "response": response]),
            sseEvent("response.in_progress", ["type": "response.in_progress", "response": baseResponse(status: "in_progress", output: [])])
        ]
    }

    private func createResponseCompletedEvent(status: String) -> String {
        var response = baseResponse(status: status, output: completedOutputItems())
        if status == "incomplete" {
            response["incomplete_details"] = ["reason": "max_output_tokens"]
        }
        return sseEvent("response.completed", ["type": "response.completed", "response": response])
    }

    private func createResponseFailedEvent(message: String, code: String) -> String {
        var response = baseResponse(status: "failed", output: completedOutputItems())
        response["error"] = ["message": message, "type": code]
        return sseEvent("response.failed", ["type": "response.failed", "response": response])
    }

    private func baseResponse(status: String, output: [[String: Any]]) -> [String: Any] {
        let usage = state.latestUsage ?? [
            "input_tokens": 0,
            "output_tokens": 0,
            "total_tokens": 0,
            "output_tokens_details": ["reasoning_tokens": 0]
        ]
        return [
            "id": state.responseId,
            "object": "response",
            "created_at": state.createdAt > 0 ? state.createdAt : Int(Date().timeIntervalSince1970),
            "status": status,
            "model": state.model,
            "output": output,
            "usage": usage
        ]
    }

    private func completedOutputItems() -> [[String: Any]] {
        let sorted = state.outputItems.sorted { $0.0 < $1.0 }
        return sorted.map { $0.1 }
    }

    private func nextOutputIndex() -> Int {
        let index = state.nextOutputIndex
        state.nextOutputIndex += 1
        return index
    }

    // MARK: - Tool response item helpers

    private func responseToolCallItemId(callId: String, chatName: String) -> String {
        if state.toolContext.isCustomToolChatName(chatName) {
            return "ctc_\(callId)"
        }
        return "fc_\(callId)"
    }

    private func responseToolCallItem(itemId: String, status: String, callId: String, chatName: String, arguments: String, reasoning: String) -> [String: Any] {
        guard let spec = state.toolContext.lookupChatName(chatName) else {
            // Unknown tool — emit as plain function_call
            var item: [String: Any] = [
                "id": itemId,
                "type": "function_call",
                "status": status,
                "call_id": callId,
                "name": chatName,
                "arguments": arguments
            ]
            if !reasoning.isEmpty { item["reasoning_content"] = reasoning }
            return item
        }

        if spec.kind == .toolSearch {
            var item: [String: Any] = [
                "type": "tool_search_call",
                "call_id": callId,
                "status": status,
                "execution": "client",
                "arguments": parseToolArgumentsObject(arguments)
            ]
            if !reasoning.isEmpty { item["reasoning_content"] = reasoning }
            return item
        }

        if spec.kind == .custom {
            var item: [String: Any] = [
                "id": itemId,
                "type": "custom_tool_call",
                "status": status,
                "call_id": callId,
                "name": spec.name,
                "input": customToolInputFromChatArguments(arguments)
            ]
            if !reasoning.isEmpty { item["reasoning_content"] = reasoning }
            return item
        }

        // function or namespace
        var item: [String: Any] = [
            "id": itemId,
            "type": "function_call",
            "status": status,
            "call_id": callId,
            "name": spec.name,
            "arguments": arguments
        ]
        if let ns = spec.namespace, !ns.isEmpty { item["namespace"] = ns }
        if !reasoning.isEmpty { item["reasoning_content"] = reasoning }
        return item
    }

    // MARK: - Helpers

    private func extractReasoning(_ delta: [String: Any]) -> String? {
        return rectifier.extractReasoningText(delta)
    }

    private func extractChatSSEError(_ chunk: [String: Any]) -> (message: String, type: String) {
        if let error = chunk["error"] as? [String: Any] {
            let message = error["message"] as? String
                ?? error["detail"] as? String
                ?? "Unknown error"
            let type = error["type"] as? String ?? error["code"] as? String ?? "server_error"
            return (message, type)
        }
        if let message = chunk["error"] as? String {
            return (message, "server_error")
        }
        return ("Unknown error", "server_error")
    }

    private func convertUsage(_ usage: [String: Any]) -> [String: Any] {
        let input = usage["prompt_tokens"] as? Int ?? usage["input_tokens"] as? Int ?? 0
        let output = usage["completion_tokens"] as? Int ?? usage["output_tokens"] as? Int ?? 0
        let total = usage["total_tokens"] as? Int ?? (input + output)
        var result: [String: Any] = [
            "input_tokens": input,
            "output_tokens": output,
            "total_tokens": total
        ]

        // cached_tokens
        if let details = usage["prompt_tokens_details"] as? [String: Any],
           let cached = details["cached_tokens"] as? Int {
            result["input_tokens_details"] = ["cached_tokens": cached]
        } else if let details = usage["input_tokens_details"] as? [String: Any],
                  let cached = details["cached_tokens"] as? Int {
            result["input_tokens_details"] = ["cached_tokens": cached]
        }

        // output_tokens_details
        if let details = usage["completion_tokens_details"] as? [String: Any] {
            var d = details
            if d["reasoning_tokens"] == nil { d["reasoning_tokens"] = 0 }
            result["output_tokens_details"] = d
        } else {
            result["output_tokens_details"] = ["reasoning_tokens": 0]
        }

        if let cacheRead = usage["cache_read_input_tokens"] { result["cache_read_input_tokens"] = cacheRead }
        if let cacheCreate = usage["cache_creation_input_tokens"] { result["cache_creation_input_tokens"] = cacheCreate }

        return result
    }

    private func responseStatusFromFinishReason(_ reason: String?) -> String {
        reason == "length" ? "incomplete" : "completed"
    }

    private func canonicalizeToolArguments(_ args: String) -> String {
        guard let data = args.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let reencoded = try? JSONSerialization.data(withJSONObject: json, options: .sortedKeys),
              let str = String(data: reencoded, encoding: .utf8) else {
            return args
        }
        return str
    }

    private func parseToolArgumentsObject(_ arguments: String) -> [String: Any] {
        let trimmed = arguments.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return [:] }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["query": arguments]
        }
        return json
    }

    private func customToolInputFromChatArguments(_ arguments: String) -> String {
        let trimmed = arguments.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return arguments
        }
        return json[customToolInputField] as? String ?? arguments
    }

    private func sseEvent(_ event: String, _ data: [String: Any]) -> String {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return "" }
        return "event: \(event)\ndata: \(jsonStr)\n\n"
    }

    // MARK: - Inline think helpers

    private func leadingThinkPrefixDecision(_ buffer: String) -> ThinkPrefixDecision {
        let trimmed = buffer.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        if trimmed.isEmpty { return .needMore }
        if trimmed.hasPrefix("<think>") { return .reasoning }
        if "<think>".hasPrefix(trimmed) { return .needMore }
        return .text
    }

    private func splitLeadingThinkBlock(_ text: String) -> (reasoning: String, answer: String)? {
        let leadingWsLen = text.count - text.drop(while: { " \t".contains($0) }).count
        let afterWs = String(text.dropFirst(leadingWsLen))
        guard afterWs.hasPrefix("<think>") else { return nil }

        let bodyStart = leadingWsLen + "<think>".count
        guard let closeRange = text[text.index(text.startIndex, offsetBy: bodyStart)...].range(of: "</think>") else {
            return nil
        }
        let closeStart = text.distance(from: text.startIndex, to: closeRange.lowerBound)
        let answerStart = closeStart + "</think>".count

        let reasoning = String(text[text.index(text.startIndex, offsetBy: bodyStart)..<text.index(text.startIndex, offsetBy: closeStart)]).trimmingCharacters(in: .whitespaces)
        var answer = String(text[text.index(text.startIndex, offsetBy: answerStart)...])
        answer = answer.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n\t "))
        return (reasoning, answer)
    }

    private func stripLeadingThinkOpenTag(_ text: String) -> String? {
        let leadingWsLen = text.count - text.drop(while: { " \t".contains($0) }).count
        let afterWs = String(text.dropFirst(leadingWsLen))
        guard afterWs.hasPrefix("<think>") else { return nil }
        return String(afterWs.dropFirst("<think>".count)).trimmingCharacters(in: .whitespaces)
    }
}

private enum ThinkPrefixDecision {
    case needMore, reasoning, text
}

private let customToolInputField = "input"

// MARK: - Deprecated compat

public struct SSEStreamTransformer: Sendable {
    public init() {}
    @available(*, deprecated, message: "Use ChatToResponsesStreamTransformer for stateful transformation")
    public func transformChatToResponsesStream(_ data: Data) -> Data? { nil }
}
