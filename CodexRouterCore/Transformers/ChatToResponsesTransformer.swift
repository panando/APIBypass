import Foundation

/// Responses API output item.
public struct ResponsesOutputItem: Codable, Equatable {
    public var type: String
    public var id: String?
    public var name: String?
    public var arguments: String?
    public var content: [ResponsesContentBlock]?

    public init(type: String, id: String? = nil, name: String? = nil, arguments: String? = nil, content: [ResponsesContentBlock]? = nil) {
        self.type = type
        self.id = id
        self.name = name
        self.arguments = arguments
        self.content = content
    }
}

/// Responses API content block.
public struct ResponsesContentBlock: Codable, Equatable {
    public var type: String
    public var text: String?

    public init(type: String, text: String? = nil) {
        self.type = type
        self.text = text
    }
}

/// Responses API response.
public struct ResponsesAPIResponse: Codable, Equatable {
    public var id: String
    public var object: String
    public var createdAt: Int
    public var model: String
    public var output: [ResponsesOutputItem]
    public var usage: ResponsesUsage?

    public init(id: String, model: String, output: [ResponsesOutputItem], usage: ResponsesUsage? = nil) {
        self.id = id
        self.object = "response"
        self.createdAt = Int(Date().timeIntervalSince1970)
        self.model = model
        self.output = output
        self.usage = usage
    }
}

/// Responses API usage.
public struct ResponsesUsage: Codable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// Transforms Chat Completions format to OpenAI Responses API format.
/// Follows cc-switch's chat_completion_to_response_with_context.
public struct ChatToResponsesTransformer: Sendable {
    private let rectifier = ReasoningRectifier()

    public init() {}

    /// Transform a Chat Completion response to Responses API format with tool context for name restoration.
    public func transform(chatResponse: ChatCompletionResponse, toolContext: CodexToolContext = CodexToolContext()) -> ResponsesAPIResponse {
        let responseId = responseIdFromChatId(chatResponse.id)
        let model = chatResponse.model

        var output: [[String: Any]] = []

        for choice in chatResponse.choices {
            let message = choice.message

            // Extract reasoning text from message
            var messageDict: [String: Any] = [:]
            if let content = message.content { messageDict["content"] = content }
            if let rc = message.reasoningContent { messageDict["reasoning_content"] = rc }

            let reasoning = extractReasoningText(messageDict)

            // Reasoning output item
            if let r = reasoning, !r.isEmpty {
                output.append([
                    "id": "rs_\(responseId)",
                    "type": "reasoning",
                    "summary": [["type": "summary_text", "text": r]]
                ])
            }

            // Message output item
            if let content = message.content {
                let text = splitLeadingThinkBlock(content).answer
                if !text.isEmpty {
                    output.append([
                        "id": "\(responseId)_msg",
                        "type": "message",
                        "status": "completed",
                        "role": "assistant",
                        "content": [["type": "output_text", "text": text, "annotations": []]]
                    ])
                }
            }

            // Tool call output items
            if let toolCalls = message.toolCalls {
                for (index, tc) in toolCalls.enumerated() {
                    let callId = tc.id.isEmpty ? "call_\(index)" : tc.id
                    let chatName = tc.function.name
                    let itemId = toolContext.isCustomToolChatName(chatName) ? "ctc_\(callId)" : "fc_\(callId)"

                    if let spec = toolContext.lookupChatName(chatName) {
                        switch spec.kind {
                        case .toolSearch:
                            output.append([
                                "type": "tool_search_call",
                                "call_id": callId,
                                "status": "completed",
                                "execution": "client",
                                "arguments": parseToolArgumentsObject(tc.function.arguments)
                            ])
                        case .custom:
                            let input = customToolInputFromChatArguments(tc.function.arguments)
                            output.append([
                                "id": itemId,
                                "type": "custom_tool_call",
                                "status": "completed",
                                "call_id": callId,
                                "name": spec.name,
                                "input": input
                            ])
                        case .function, .namespace:
                            var item: [String: Any] = [
                                "id": itemId,
                                "type": "function_call",
                                "status": "completed",
                                "call_id": callId,
                                "name": spec.name,
                                "arguments": canonicalizeToolArguments(tc.function.arguments)
                            ]
                            if let ns = spec.namespace, !ns.isEmpty { item["namespace"] = ns }
                            output.append(item)
                        }
                    } else {
                        output.append([
                            "id": itemId,
                            "type": "function_call",
                            "status": "completed",
                            "call_id": callId,
                            "name": chatName,
                            "arguments": canonicalizeToolArguments(tc.function.arguments)
                        ])
                    }
                }
            }
        }

        // Usage
        var usage: ResponsesUsage?
        if let chatUsage = chatResponse.usage {
            usage = ResponsesUsage(
                inputTokens: chatUsage.promptTokens,
                outputTokens: chatUsage.completionTokens
            )
        }

        // Build output items
        let outputItems: [ResponsesOutputItem] = output.map { item in
            let type = item["type"] as? String ?? "message"
            let id = item["id"] as? String
            let name = item["name"] as? String
            let arguments = item["arguments"] as? String
            let content = (item["content"] as? [[String: Any]])?.map { block in
                ResponsesContentBlock(type: block["type"] as? String ?? "output_text", text: block["text"] as? String)
            }
            return ResponsesOutputItem(type: type, id: id, name: name, arguments: arguments, content: content)
        }

        return ResponsesAPIResponse(
            id: responseId,
            model: model,
            output: outputItems,
            usage: usage
        )
    }

    // MARK: - Helpers

    private func extractReasoningText(_ value: [String: Any]) -> String? {
        rectifier.extractReasoningText(value)
    }

    private func responseIdFromChatId(_ id: String) -> String {
        if id.hasPrefix("resp_") { return id }
        return "resp_\(id)"
    }

    private func splitLeadingThinkBlock(_ text: String) -> (reasoning: String?, answer: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let leadingWsLen = text.count - trimmed.count
        let afterWs = String(text.dropFirst(leadingWsLen == text.count ? 0 : leadingWsLen))
        guard afterWs.hasPrefix("<think>"),
              let closeRange = afterWs.range(of: "</think>") else {
            return (nil, text)
        }
        let reasoning = String(afterWs[afterWs.index(afterWs.startIndex, offsetBy: "<think>".count)..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let answer = String(afterWs[closeRange.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n\t "))
        if reasoning.isEmpty, answer.isEmpty {
            return (nil, text)
        }
        return (reasoning.isEmpty ? nil : reasoning, answer)
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
        return json["input"] as? String ?? arguments
    }
}
