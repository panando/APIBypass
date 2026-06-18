import Foundation

/// Anthropic ↔ OpenAI API 格式双向转换器
final class FormatTranslator {

    // MARK: - cch Billing Header Stripping (Solution 1)

    private let anthropicBillingHeaderPrefix = "x-anthropic-billing-header:"

    /// Strip a leading `x-anthropic-billing-header` line from system text.
    ///
    /// Claude Code sends a dynamic `cch=...` value in this header. When placed at the
    /// start of `system` / `instructions`, it breaks prefix-based prompt caching (#2350).
    func stripLeadingAnthropicBillingHeader(_ text: String) -> String {
        guard text.hasPrefix(anthropicBillingHeaderPrefix) else {
            return text
        }
        guard let firstNewline = text.firstIndex(where: { $0.isNewline }) else {
            return ""
        }
        var remainder = String(text[text.index(after: firstNewline)...])
        if remainder.hasPrefix("\n") {
            remainder = String(remainder.dropFirst())
        } else if remainder.hasPrefix("\r\n") {
            remainder = String(remainder.dropFirst(2))
        }
        return remainder
    }

    func shouldRectifyThinkingSignature(_ errorMessage: String?) -> Bool {
        guard let msg = errorMessage else { return false }
        let lower = msg.lowercased()
        if lower.contains("invalid") && lower.contains("signature") && lower.contains("thinking") && lower.contains("block") {
            return true
        }
        if lower.contains("thought signature") && (lower.contains("not valid") || lower.contains("invalid")) {
            return true
        }
        if lower.contains("must start with a thinking block") {
            return true
        }
        if lower.contains("expected") && (lower.contains("thinking") || lower.contains("redacted_thinking")) && lower.contains("found") && lower.contains("tool_use") {
            return true
        }
        if lower.contains("signature") && lower.contains("field required") {
            return true
        }
        if lower.contains("signature") && lower.contains("extra inputs are not permitted") {
            return true
        }
        if (lower.contains("thinking") || lower.contains("redacted_thinking")) && lower.contains("cannot be modified") {
            return true
        }
        if lower.contains("illegal request") || lower.contains("invalid request") {
            return true
        }
        return false
    }

    func shouldRectifyThinkingBudget(_ errorMessage: String?) -> Bool {
        guard let msg = errorMessage else { return false }
        let lower = msg.lowercased()
        let hasBudget = lower.contains("budget_tokens") || lower.contains("budget tokens")
        let hasThinking = lower.contains("thinking")
        let has1024 = lower.contains("greater than or equal to 1024") || lower.contains(">= 1024") || (lower.contains("1024") && lower.contains("input should be"))
        return hasBudget && hasThinking && has1024
    }

    func rectifyAnthropicRequest(_ body: inout [String: Any]) -> RectifierResult {
        var result = RectifierResult()
        guard let messages = body["messages"] as? [[String: Any]] else { return result }
        var newMessages: [[String: Any]] = []
        for msg in messages {
            guard let content = msg["content"] as? [[String: Any]] else {
                newMessages.append(msg)
                continue
            }
            var newContent: [[String: Any]] = []
            var modified = false
            for block in content {
                let type = block["type"] as? String ?? ""
                if type == "thinking" {
                    result.removedThinkingBlocks += 1
                    modified = true
                    continue
                }
                if type == "redacted_thinking" {
                    result.removedRedactedThinkingBlocks += 1
                    modified = true
                    continue
                }
                var newBlock = block
                if newBlock.removeValue(forKey: "signature") != nil {
                    result.removedSignatureFields += 1
                    modified = true
                }
                newContent.append(newBlock)
            }
            if modified {
                result.applied = true
                var newMsg = msg
                newMsg["content"] = newContent
                newMessages.append(newMsg)
            } else {
                newMessages.append(msg)
            }
        }
        if result.applied {
            body["messages"] = newMessages
        }
        if shouldRemoveTopLevelThinking(body: body) {
            body.removeValue(forKey: "thinking")
            result.applied = true
            result.removedTopLevelThinking = true
        }
        return result
    }

    private func shouldRemoveTopLevelThinking(body: [String: Any]) -> Bool {
        guard let thinking = body["thinking"] as? [String: Any],
              let type = thinking["type"] as? String,
              type == "enabled" else { return false }
        guard let messages = body["messages"] as? [[String: Any]] else { return false }
        guard let lastAssistant = messages.last(where: { $0["role"] as? String == "assistant" }),
              let content = lastAssistant["content"] as? [[String: Any]],
              !content.isEmpty else { return false }
        let firstType = content.first?["type"] as? String ?? ""
        if firstType == "thinking" || firstType == "redacted_thinking" { return false }
        return firstType == "tool_use"
    }

    func rectifyThinkingBudget(_ body: inout [String: Any]) -> BudgetRectifierResult {
        let before = budgetSnapshot(body)
        if before.thinkingType == "adaptive" {
            return BudgetRectifierResult(applied: false, before: before, after: before)
        }
        if body["thinking"] == nil || !(body["thinking"] is [String: Any]) {
            body["thinking"] = [String: Any]()
        }
        guard var thinking = body["thinking"] as? [String: Any] else {
            return BudgetRectifierResult(applied: false, before: before, after: before)
        }
        thinking["type"] = "enabled"
        thinking["budget_tokens"] = 32000
        body["thinking"] = thinking
        if let maxTokens = body["max_tokens"] as? Int {
            if maxTokens <= 32001 {
                body["max_tokens"] = 64000
            }
        } else {
            body["max_tokens"] = 64000
        }
        let after = budgetSnapshot(body)
        return BudgetRectifierResult(applied: before != after, before: before, after: after)
    }

    private func budgetSnapshot(_ body: [String: Any]) -> BudgetSnapshot {
        let maxTokens = body["max_tokens"] as? Int
        let thinking = body["thinking"] as? [String: Any]
        let type = thinking?["type"] as? String
        let budget = thinking?["budget_tokens"] as? Int
        return BudgetSnapshot(maxTokens: maxTokens, thinkingType: type, thinkingBudgetTokens: budget)
    }

    // MARK: - Request Translation

    /// Anthropic Messages API → OpenAI Chat Completions API
    func anthropicToOpenAIRequest(_ json: [String: Any]) -> [String: Any] {
        var out = json

        // system → prepend to messages as system role
        let systemContent = extractSystemContent(json["system"])
        var oaiMessages: [[String: Any]] = []
        if let sys = systemContent {
            oaiMessages.append(["role": "system", "content": sys])
        }

        // messages
        if let messages = json["messages"] as? [[String: Any]] {
            for msg in messages {
                let role = msg["role"] as? String ?? "user"
                let content = msg["content"]
                let converted = contentToOAIMessages(role: role, content: content)
                oaiMessages.append(contentsOf: converted)
            }
        }
        out["messages"] = oaiMessages

        // tools
        if let tools = json["tools"] as? [[String: Any]] {
            out["tools"] = tools.map { anthropicToolToOpenAI($0) }
        }

        // tool_choice
        if let tc = json["tool_choice"] as? [String: Any] {
            out["tool_choice"] = anthropicToolChoiceToOpenAI(tc)
        }

        // thinking → enable_thinking + thinking_budget
        // 仅在 thinking 明确启用时才添加字段，避免发送上游不认识的字段
        if let thinking = json["thinking"] as? [String: Any] {
            let type = thinking["type"] as? String ?? ""
            if type == "enabled" {
                out["enable_thinking"] = true
                if let budget = thinking["budget_tokens"] as? Int {
                    out["thinking_budget"] = budget
                }
            }
        }

        // stop_sequences → stop
        if let stopSeq = json["stop_sequences"] {
            out["stop"] = stopSeq
        }

        // Remove Anthropic-specific fields
        out.removeValue(forKey: "system")
        out.removeValue(forKey: "stop_sequences")
        out.removeValue(forKey: "thinking")
        out.removeValue(forKey: "metadata")
        out.removeValue(forKey: "top_k")
        out.removeValue(forKey: "context_management")
        out.removeValue(forKey: "output_config")

        return out
    }

    /// OpenAI Chat Completions API → Anthropic Messages API
    func openAIToAnthropicRequest(_ json: [String: Any]) -> [String: Any] {
        var out = json

        // Extract system messages → top-level system
        var systemTexts: [String] = []
        var anthropicMessages: [[String: Any]] = []

        if let messages = json["messages"] as? [[String: Any]] {
            for msg in messages {
                let role = msg["role"] as? String ?? "user"
                switch role {
                case "system", "developer":
                    if let text = oaiContentText(msg["content"]) {
                        systemTexts.append(text)
                    }
                case "tool":
                    let content = oaiContentText(msg["content"]) ?? ""
                    anthropicMessages.append([
                        "role": "user",
                        "content": [[
                            "type": "tool_result",
                            "tool_use_id": msg["tool_call_id"] ?? "",
                            "content": content
                        ]]
                    ])
                case "assistant":
                    anthropicMessages.append(oaiAssistantToAnthropic(msg))
                default:
                    let role = role.isEmpty ? "user" : role
                    anthropicMessages.append([
                        "role": role,
                        "content": oaiContentToAnthropicBlocks(msg["content"])
                    ])
                }
            }
        }

        if !systemTexts.isEmpty {
            out["system"] = systemTexts.joined(separator: "\n\n")
        }
        out["messages"] = anthropicMessages

        // tools
        if let tools = json["tools"] as? [[String: Any]] {
            out["tools"] = tools.map { openAIToolToAnthropic($0) }
        }

        // tool_choice
        if let tc = json["tool_choice"] as? [String: Any] {
            out["tool_choice"] = openAIToolChoiceToAnthropic(tc)
        } else if let tcStr = json["tool_choice"] as? String {
            out["tool_choice"] = openAIToolChoiceStringToAnthropic(tcStr)
        }

        // enable_thinking → thinking
        if let et = json["enable_thinking"] as? Bool {
            if et {
                var thinking: [String: Any] = ["type": "enabled"]
                if let budget = json["thinking_budget"] as? Int {
                    thinking["budget_tokens"] = budget
                }
                out["thinking"] = thinking
            } else {
                out["thinking"] = ["type": "disabled"]
            }
        }

        // stop → stop_sequences
        if let stop = json["stop"] {
            out["stop_sequences"] = stop
        }

        // Remove OpenAI-specific fields
        out.removeValue(forKey: "stop")
        out.removeValue(forKey: "enable_thinking")
        out.removeValue(forKey: "thinking_budget")
        out.removeValue(forKey: "stream_options")

        return out
    }

    // MARK: - Non-streaming Response Translation

    /// OpenAI Chat Completions response → Anthropic Messages response
    func openAIToAnthropicResponse(_ json: [String: Any], model: String) -> [String: Any] {
        var content: [[String: Any]] = []
        var stopReason = "end_turn"

        if let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any] {

            // Reasoning/thinking content (OpenAI: reasoning_content → Anthropic: thinking block)
            if let reasoning = message["reasoning_content"] as? String, !reasoning.isEmpty {
                content.append([
                    "type": "thinking",
                    "thinking": reasoning,
                    "signature": "Eq4EAC8KAQw="
                ])
            }

            // Text content
            if let text = message["content"] as? String, !text.isEmpty {
                content.append(["type": "text", "text": text])
            }

            // Tool calls
            if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                for tc in toolCalls {
                    var input: Any = [String: Any]()
                    if let argsStr = tc["function"] as? [String: Any],
                       let arguments = argsStr["arguments"] as? String,
                       let data = arguments.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) {
                        input = parsed
                    }
                    content.append([
                        "type": "tool_use",
                        "id": tc["id"] ?? "",
                        "name": (tc["function"] as? [String: Any])?["name"] ?? "",
                        "input": input
                    ])
                }
                stopReason = "tool_use"
            }

            // Finish reason mapping
            if let finish = choices.first?["finish_reason"] as? String {
                stopReason = mapOpenAIFinishReason(finish)
            }
        }

        // Usage mapping
        let oaiUsage = json["usage"] as? [String: Any]
        let usage = mapOpenAIUsage(oaiUsage)

        return [
            "id": json["id"] ?? "msg_apibypass",
            "type": "message",
            "role": "assistant",
            "model": model,
            "content": content,
            "stop_reason": stopReason,
            "stop_sequence": NSNull(),
            "usage": usage
        ]
    }

    /// Anthropic Messages response → OpenAI Chat Completions response
    func anthropicToOpenAIResponse(_ json: [String: Any], model: String) -> [String: Any] {
        var textContent = ""
        var toolCalls: [[String: Any]] = []
        var finishReason = "stop"

        if let content = json["content"] as? [[String: Any]] {
            for block in content {
                switch block["type"] as? String {
                case "text":
                    if let t = block["text"] as? String {
                        textContent += t
                    }
                case "tool_use":
                    let argsData = try? JSONSerialization.data(withJSONObject: block["input"] ?? [:])
                    let argsStr = argsData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    toolCalls.append([
                        "id": block["id"] ?? "",
                        "type": "function",
                        "function": [
                            "name": block["name"] ?? "",
                            "arguments": argsStr
                        ]
                    ])
                    finishReason = "tool_calls"
                default:
                    break
                }
            }
        }

        if let sr = json["stop_reason"] as? String, sr == "tool_use" {
            finishReason = "tool_calls"
        }

        var message: [String: Any] = ["role": "assistant", "content": textContent]
        if !toolCalls.isEmpty {
            message["tool_calls"] = toolCalls
        }

        let anthroUsage = json["usage"] as? [String: Any]
        let usage = mapAnthropicUsageToOpenAI(anthroUsage)

        return [
            "id": json["id"] ?? "chatcmpl_apibypass",
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": model,
            "choices": [[
                "index": 0,
                "message": message,
                "finish_reason": finishReason
            ]],
            "usage": usage
        ]
    }

    // MARK: - Convenience

    func translateRequest(_ data: Data, from source: APIFormat, to target: APIFormat) throws -> Data {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProxyError.invalidJSON
        }
        let result: [String: Any]
        switch (source, target) {
        case (.anthropic, .openai):
            result = anthropicToOpenAIRequest(json)
        case (.openai, .anthropic):
            result = openAIToAnthropicRequest(json)
        default:
            return data
        }
        return try JSONSerialization.data(withJSONObject: result)
    }

    func translateResponse(_ data: Data, from source: APIFormat, to target: APIFormat, model: String) throws -> Data {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProxyError.invalidJSON
        }
        let result: [String: Any]
        switch (source, target) {
        case (.openai, .anthropic):
            result = openAIToAnthropicResponse(json, model: model)
        case (.anthropic, .openai):
            result = anthropicToOpenAIResponse(json, model: model)
        default:
            return data
        }
        return try JSONSerialization.data(withJSONObject: result)
    }

    // MARK: - Private Helpers

    private func extractSystemContent(_ system: Any?) -> String? {
        guard let sys = system else { return nil }
        if let s = sys as? String { return s }
        if let blocks = sys as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return nil
    }

    // MARK: Anthropic → OpenAI message conversion

    private func contentToOAIMessages(role: String, content: Any?) -> [[String: Any]] {
        if let s = content as? String {
            return [["role": role, "content": s]]
        }
        guard let blocks = content as? [[String: Any]] else {
            return [["role": role, "content": ""]]
        }

        var textParts: [String] = []
        var imageParts: [[String: Any]] = []
        var toolCalls: [[String: Any]] = []
        var toolResults: [[String: Any]] = []
        var reasoningParts: [String] = []

        for block in blocks {
            switch block["type"] as? String {
            case "text":
                if let t = block["text"] as? String { textParts.append(t) }
            case "thinking":
                if let t = block["thinking"] as? String, !t.isEmpty {
                    reasoningParts.append(t)
                }
            case "image":
                if let img = convertAnthropicImageToOpenAI(block) {
                    imageParts.append(img)
                }
            case "tool_use":
                let id = block["id"] as? String ?? ""
                let name = block["name"] as? String ?? ""
                let input = block["input"] ?? [String: Any]()
                let argsData = try? JSONSerialization.data(withJSONObject: input)
                let argsStr = argsData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                toolCalls.append([
                    "id": id,
                    "type": "function",
                    "function": ["name": name, "arguments": argsStr]
                ])
            case "tool_result":
                let toolUseId = block["tool_use_id"] as? String ?? ""
                let resultContent: String
                if let s = block["content"] as? String {
                    resultContent = s
                } else if let arr = block["content"] as? [[String: Any]] {
                    resultContent = arr.compactMap { b -> String? in
                        guard (b["type"] as? String) == "text" else { return nil }
                        return b["text"] as? String
                    }.joined()
                } else {
                    resultContent = ""
                }
                toolResults.append([
                    "role": "tool",
                    "tool_call_id": toolUseId,
                    "content": resultContent
                ])
            default:
                break
            }
        }

        var messages: [[String: Any]] = []

        // Tool results first (they must come right after the assistant tool_calls message in OpenAI format)
        messages.append(contentsOf: toolResults)

        if !toolCalls.isEmpty {
            var msg: [String: Any] = ["role": "assistant", "tool_calls": toolCalls]
            if !textParts.isEmpty {
                msg["content"] = textParts.joined()
            }
            if !reasoningParts.isEmpty {
                msg["reasoning_content"] = reasoningParts.joined()
            }
            messages.insert(msg, at: 0)
        } else if !textParts.isEmpty || !imageParts.isEmpty {
            if !imageParts.isEmpty {
                var parts: [[String: Any]] = []
                for t in textParts { parts.append(["type": "text", "text": t]) }
                parts.append(contentsOf: imageParts)
                var msg: [String: Any] = ["role": role, "content": parts]
                if !reasoningParts.isEmpty && role == "assistant" {
                    msg["reasoning_content"] = reasoningParts.joined()
                }
                messages.append(msg)
            } else {
                var msg: [String: Any] = ["role": role, "content": textParts.joined()]
                if !reasoningParts.isEmpty && role == "assistant" {
                    msg["reasoning_content"] = reasoningParts.joined()
                }
                messages.append(msg)
            }
        } else if !reasoningParts.isEmpty && role == "assistant" {
            messages.append([
                "role": "assistant",
                "content": "",
                "reasoning_content": reasoningParts.joined()
            ])
        }

        return messages
    }

    private func convertAnthropicImageToOpenAI(_ block: [String: Any]) -> [String: Any]? {
        guard let source = block["source"] as? [String: Any] else { return nil }
        let sourceType = source["type"] as? String ?? ""
        switch sourceType {
        case "base64":
            let mediaType = source["media_type"] as? String ?? "image/png"
            let data = source["data"] as? String ?? ""
            return ["type": "image_url", "image_url": ["url": "data:\(mediaType);base64,\(data)"]]
        case "url":
            let url = source["url"] as? String ?? ""
            return ["type": "image_url", "image_url": ["url": url]]
        default:
            return nil
        }
    }

    // MARK: OpenAI → Anthropic message conversion

    private func oaiContentText(_ content: Any?) -> String? {
        guard let c = content else { return nil }
        if let s = c as? String { return s }
        if let parts = c as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        if let parts = c as? [Any] {
            return parts.compactMap { ($0 as? [String: Any])?["text"] as? String }.joined()
        }
        return nil
    }

    private func oaiContentToAnthropicBlocks(_ content: Any?) -> Any {
        guard let c = content else { return "" }
        if let s = c as? String { return s }
        if let parts = c as? [[String: Any]] {
            var blocks: [[String: Any]] = []
            for part in parts {
                switch part["type"] as? String {
                case "text", "input_text", "output_text":
                    if let t = part["text"] as? String, !t.isEmpty {
                        blocks.append(["type": "text", "text": t])
                    }
                case "image_url":
                    if let img = convertOpenAIImageToAnthropic(part) {
                        blocks.append(img)
                    }
                default:
                    break
                }
            }
            return blocks.isEmpty ? "" : blocks
        }
        if let parts = c as? [Any] {
            var blocks: [[String: Any]] = []
            for item in parts {
                guard let part = item as? [String: Any] else { continue }
                switch part["type"] as? String {
                case "text", "input_text", "output_text":
                    if let t = part["text"] as? String, !t.isEmpty {
                        blocks.append(["type": "text", "text": t])
                    }
                case "image_url", "input_image":
                    if let img = convertOpenAIImageToAnthropic(part) {
                        blocks.append(img)
                    }
                default:
                    break
                }
            }
            return blocks.isEmpty ? "" : blocks
        }
        return "\(c)"
    }

    private func convertOpenAIImageToAnthropic(_ part: [String: Any]) -> [String: Any]? {
        // Try image_url object first
        if let imageUrl = part["image_url"] as? [String: Any],
           let url = imageUrl["url"] as? String {
            return anthropicImageBlock(url: url)
        }
        // Try direct url field
        if let url = part["url"] as? String {
            return anthropicImageBlock(url: url)
        }
        // Try string value
        if let url = part["image_url"] as? String {
            return anthropicImageBlock(url: url)
        }
        return nil
    }

    private func anthropicImageBlock(url: String) -> [String: Any] {
        if url.hasPrefix("data:") {
            // Parse data URI → extract media type and base64 data
            let stripped = url.replacingOccurrences(of: "data:", with: "")
            let parts = stripped.split(separator: ",", maxSplits: 1)
            if parts.count == 2 {
                let header = String(parts[0])
                let data = String(parts[1])
                let mediaType = header.split(separator: ";").first.map(String.init) ?? "image/png"
                return [
                    "type": "image",
                    "source": ["type": "base64", "media_type": mediaType, "data": data]
                ]
            }
        }
        return [
            "type": "image",
            "source": ["type": "url", "url": url]
        ]
    }

    private func oaiAssistantToAnthropic(_ msg: [String: Any]) -> [String: Any] {
        var blocks: [[String: Any]] = []

        // Text content
        if let text = oaiContentText(msg["content"]), !text.isEmpty {
            blocks.append(["type": "text", "text": text])
        }

        // Tool calls
        if let toolCalls = msg["tool_calls"] as? [[String: Any]] {
            for tc in toolCalls {
                let funcInfo = tc["function"] as? [String: Any]
                let argsStr = funcInfo?["arguments"] as? String ?? "{}"
                let input: Any
                if let data = argsStr.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) {
                    input = parsed
                } else {
                    input = argsStr
                }
                blocks.append([
                    "type": "tool_use",
                    "id": tc["id"] ?? "",
                    "name": funcInfo?["name"] ?? "",
                    "input": input
                ])
            }
        }

        return ["role": "assistant", "content": blocks]
    }

    // MARK: Tool conversions

    private func anthropicToolToOpenAI(_ tool: [String: Any]) -> [String: Any] {
        return [
            "type": "function",
            "function": [
                "name": tool["name"] ?? "",
                "description": tool["description"] ?? "",
                "parameters": tool["input_schema"] ?? [String: Any]()
            ]
        ]
    }

    private func openAIToolToAnthropic(_ tool: [String: Any]) -> [String: Any] {
        let funcInfo = tool["function"] as? [String: Any] ?? [:]
        return [
            "name": funcInfo["name"] ?? "",
            "description": funcInfo["description"] ?? "",
            "input_schema": funcInfo["parameters"] ?? [String: Any]()
        ]
    }

    private func anthropicToolChoiceToOpenAI(_ tc: [String: Any]) -> Any {
        switch tc["type"] as? String {
        case "auto": return "auto"
        case "any":  return "required"
        case "tool":
            return ["type": "function", "function": ["name": tc["name"] ?? ""]]
        default: return "auto"
        }
    }

    private func openAIToolChoiceToAnthropic(_ tc: [String: Any]) -> [String: Any] {
        switch tc["type"] as? String {
        case "function":
            let name = (tc["function"] as? [String: Any])?["name"] as? String ?? ""
            return ["type": "tool", "name": name]
        default: return ["type": "auto"]
        }
    }

    private func openAIToolChoiceStringToAnthropic(_ tc: String) -> [String: Any] {
        switch tc {
        case "auto":     return ["type": "auto"]
        case "required": return ["type": "any"]
        case "none":     return ["type": "auto"]
        default:         return ["type": "auto"]
        }
    }

    // MARK: Usage mapping

    private func mapOpenAIUsage(_ usage: [String: Any]?) -> [String: Any] {
        guard let u = usage else {
            return ["input_tokens": 0, "output_tokens": 0]
        }
        var out: [String: Any] = [
            "input_tokens": u["prompt_tokens"] ?? 0,
            "output_tokens": u["completion_tokens"] ?? 0
        ]
        // Cache tokens
        if let details = u["prompt_tokens_details"] as? [String: Any],
           let cached = details["cached_tokens"] as? Int {
            out["cache_read_input_tokens"] = cached
        }
        if let details = u["input_tokens_details"] as? [String: Any],
           let cached = details["cached_tokens"] as? Int {
            out["cache_read_input_tokens"] = cached
        }
        if let cached = u["cached_tokens"] as? Int {
            out["cache_read_input_tokens"] = cached
        }
        return out
    }

    private func mapAnthropicUsageToOpenAI(_ usage: [String: Any]?) -> [String: Any] {
        guard let u = usage else {
            return ["prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0]
        }
        let input = u["input_tokens"] as? Int ?? 0
        let output = u["output_tokens"] as? Int ?? 0
        var out: [String: Any] = [
            "prompt_tokens": input,
            "completion_tokens": output,
            "total_tokens": input + output
        ]
        if let cached = u["cache_read_input_tokens"] as? Int {
            out["prompt_tokens_details"] = ["cached_tokens": cached]
        }
        return out
    }

    // MARK: Finish reason mapping

    private func mapOpenAIFinishReason(_ reason: String) -> String {
        switch reason {
        case "stop":        return "end_turn"
        case "length":      return "max_tokens"
        case "tool_calls":  return "tool_use"
        case "content_filter": return "end_turn"
        default:            return "end_turn"
        }
    }
}
