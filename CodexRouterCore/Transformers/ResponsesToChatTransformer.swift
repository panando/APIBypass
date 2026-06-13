import Foundation

/// Chat completion message.
public struct ChatMessage: Codable, Equatable {
    public var role: String
    public var content: String?
    public var toolCalls: [ToolCall]?
    public var reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case reasoningContent = "reasoning_content"
    }

    public init(role: String, content: String? = nil, toolCalls: [ToolCall]? = nil, reasoningContent: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.reasoningContent = reasoningContent
    }
}

/// Tool call in chat completion.
public struct ToolCall: Codable, Equatable {
    public var id: String
    public var type: String
    public var function: FunctionCall

    public init(id: String, function: FunctionCall) {
        self.id = id
        self.type = "function"
        self.function = function
    }
}

/// Function call details.
public struct FunctionCall: Codable, Equatable {
    public var name: String
    public var arguments: String

    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }
}

/// Chat completion choice.
public struct ChatChoice: Codable, Equatable {
    public var index: Int
    public var message: ChatMessage
    public var finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }

    public init(index: Int, message: ChatMessage, finishReason: String? = nil) {
        self.index = index
        self.message = message
        self.finishReason = finishReason
    }
}

/// Token usage.
public struct Usage: Codable, Equatable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }

    public init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = promptTokens + completionTokens
    }
}

/// Chat completion response.
public struct ChatCompletionResponse: Codable, Equatable {
    public var id: String
    public var object: String
    public var created: Int
    public var model: String
    public var choices: [ChatChoice]
    public var usage: Usage?

    public init(id: String, model: String, choices: [ChatChoice], usage: Usage? = nil) {
        self.id = id
        self.object = "chat.completion"
        self.created = Int(Date().timeIntervalSince1970)
        self.model = model
        self.choices = choices
        self.usage = usage
    }
}

/// Transforms OpenAI Responses API format to Chat Completions format.
public struct ResponsesToChatTransformer {

    public init() {}

    public func transform(responsesJSON: String) throws -> ChatCompletionResponse {
        guard let data = responsesJSON.data(using: .utf8) else {
            throw TransformerError.invalidInput
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let id = json["id"] as? String ?? "unknown"
        let model = json["model"] as? String ?? "unknown"

        var content = ""
        var toolCalls: [ToolCall] = []
        var finishReason: String?

        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                let type = item["type"] as? String

                switch type {
                case "message":
                    if let messageContent = item["content"] as? [[String: Any]] {
                        for block in messageContent {
                            if let text = block["text"] as? String {
                                content += text
                            }
                        }
                    }

                case "function_call":
                    if let callId = item["id"] as? String,
                       let name = item["name"] as? String,
                       let arguments = item["arguments"] as? String {
                        toolCalls.append(ToolCall(
                            id: callId,
                            function: FunctionCall(name: name, arguments: arguments)
                        ))
                    }
                    finishReason = "tool_calls"

                default:
                    break
                }
            }
        }

        var usage: Usage?
        if let usageDict = json["usage"] as? [String: Any] {
            let inputTokens = usageDict["input_tokens"] as? Int ?? 0
            let outputTokens = usageDict["output_tokens"] as? Int ?? 0
            usage = Usage(promptTokens: inputTokens, completionTokens: outputTokens)
        }

        let message = ChatMessage(role: "assistant", content: content.isEmpty ? nil : content, toolCalls: toolCalls.isEmpty ? nil : toolCalls)

        if finishReason == nil && !content.isEmpty {
            finishReason = "stop"
        }

        return ChatCompletionResponse(
            id: id,
            model: model,
            choices: [ChatChoice(index: 0, message: message, finishReason: finishReason)],
            usage: usage
        )
    }
}

public enum TransformerError: Error, LocalizedError {
    case invalidInput
    case transformationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Invalid input data"
        case .transformationFailed(let message):
            return "Transformation failed: \(message)"
        }
    }
}
