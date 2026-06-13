import Foundation

/// Adapts reasoning parameters for different AI platforms.
/// Follows cc-switch's transform_codex_chat.rs apply_reasoning_options and map_reasoning_effort.
public struct ReasoningRectifier: Sendable {

    public init() {}

    // MARK: - Reasoning application (during Responses→Chat conversion)

    /// Apply reasoning options during Responses→Chat Completions conversion.
    /// Reads reasoning/effort from the original Responses body, writes thinking/effort params to the Chat request.
    public func applyReasoning(
        chatRequest: inout [String: Any],
        responsesBody: [String: Any],
        config: ReasoningConfig?,
        model: String
    ) {
        guard let config = config else {
            // Without config: pass through reasoning_effort if model supports it
            if supportsReasoningEffort(model: model) {
                if let effort = (responsesBody["reasoning"] as? [String: Any])?["effort"] as? String {
                    chatRequest["reasoning_effort"] = effort
                }
            }
            return
        }

        let supportsEffort = config.supportsEffort ?? false
        let supportsThinking = config.supportsThinking ?? false || supportsEffort

        guard let reasoningEnabled = reasoningRequested(body: responsesBody) else {
            return
        }

        // Write thinking param
        if supportsThinking {
            let thinkingParam = (config.thinkingParam ?? "thinking").trimmingCharacters(in: .whitespaces).lowercased()
            switch thinkingParam {
            case "thinking":
                chatRequest["thinking"] = [
                    "type": reasoningEnabled ? "enabled" : "disabled"
                ]
            case "enable_thinking":
                chatRequest["enable_thinking"] = reasoningEnabled
            case "reasoning_split":
                chatRequest["reasoning_split"] = reasoningEnabled
            default:
                break // "none" or unknown → skip
            }
        }

        // If reasoning explicitly disabled
        if !reasoningEnabled {
            let effortParam = (config.effortParam ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            // OpenRouter native reasoning.effort supports explicit "none" (semantics: fully disable reasoning).
            // For platforms with reasoning.effort param, faithfully forward {"reasoning":{"effort":"none"}}
            // so models that default to thinking can be explicitly turned off.
            if effortParam == "reasoning.effort" {
                chatRequest["reasoning"] = ["effort": "none"]
            }
            return
        }

        guard supportsEffort else { return }

        guard let effort = (responsesBody["reasoning"] as? [String: Any])?["effort"] as? String else {
            return
        }
        guard let mapped = mapEffortValue(effort, mode: config.effortValueMode) else {
            return
        }

        let effortParam = (config.effortParam ?? "reasoning_effort").trimmingCharacters(in: .whitespaces).lowercased()
        switch effortParam {
        case "reasoning_effort":
            chatRequest["reasoning_effort"] = mapped
        case "reasoning.effort":
            // OpenRouter native normalized object: reasoning.effort gets translated by OpenRouter
            // into the correct reasoning params for each underlying model (OpenAI/Grok/Gemini/Anthropic).
            // Construct from empty object so we don't leak residual reasoning fields.
            chatRequest["reasoning"] = ["effort": mapped]
        default:
            break
        }
    }

    // MARK: - Effort mapping

    /// Map Codex reasoning effort value to provider-specific value.
    /// Follows cc-switch's map_reasoning_effort exactly.
    private func mapEffortValue(_ effort: String, mode: String?) -> String? {
        let effort = effort.trimmingCharacters(in: .whitespaces).lowercased()
        if ["none", "off", "disabled"].contains(effort) {
            return nil
        }

        switch mode ?? "passthrough" {
        case "deepseek":
            switch effort {
            case "max", "xhigh": return "max"
            default: return "high"
            }
        case "low_high":
            switch effort {
            case "minimal", "low": return "low"
            default: return "high"
            }
        case "openrouter":
            // OpenRouter effort enum: xhigh|high|medium|low|minimal (no max).
            // max is Codex/some model's extended tier, illegal for OpenRouter → clamp to xhigh.
            switch effort {
            case "max", "xhigh": return "xhigh"
            case "high": return "high"
            case "medium": return "medium"
            case "low": return "low"
            case "minimal": return "minimal"
            default: return nil
            }
        default:
            // Passthrough: filter to known valid values only
            switch effort {
            case "minimal": return "minimal"
            case "low": return "low"
            case "medium": return "medium"
            case "high": return "high"
            case "xhigh": return "xhigh"
            case "max": return "max"
            default: return nil
            }
        }
    }

    /// Check if the original Responses body requests reasoning.
    /// Returns nil if reasoning field is absent entirely (not explicitly enabled or disabled).
    private func reasoningRequested(body: [String: Any]) -> Bool? {
        if let reasoning = body["reasoning"] as? [String: Any],
           let effort = reasoning["effort"] as? String {
            let effort = effort.trimmingCharacters(in: .whitespaces).lowercased()
            if ["none", "off", "disabled"].contains(effort) {
                return false
            }
            return true
        }

        if let reasoning = body["reasoning"] {
            return !(reasoning is NSNull)
        }

        return nil
    }

    /// Check if a model name suggests reasoning_effort support (for passthrough without config).
    private func supportsReasoningEffort(model: String) -> Bool {
        let model = model.lowercased()
        // OpenAI o-series, GPT-5+, DeepSeek reasoning models etc.
        let patterns = ["o1", "o3", "o4", "gpt-5", "deepseek-r", "deepseek-v"]
        return patterns.contains(where: model.contains)
    }

    // MARK: - Reasoning extraction

    /// Extract reasoning text from a Chat response delta or message.
    /// Follows cc-switch's extract_reasoning_field_text: checks reasoning_content → reasoning string → reasoning object (content/text/summary) → reasoning_details.
    public func extractReasoningText(_ value: [String: Any]) -> String? {
        // reasoning_content string
        if let text = value["reasoning_content"] as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            return text
        }
        // reasoning string
        if let text = value["reasoning"] as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            return text
        }
        // reasoning object (OpenRouter)
        if let reasoning = value["reasoning"] as? [String: Any] {
            for key in ["content", "text", "summary"] {
                if let text = reasoning[key] as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    return text
                }
            }
        }
        // reasoning_details array
        if let details = value["reasoning_details"] {
            return extractReasoningDetailsText(details)
        }
        return nil
    }

    private func extractReasoningDetailsText(_ value: Any) -> String? {
        if let text = value as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            return text
        }
        if let parts = value as? [[String: Any]] {
            let text = parts.compactMap { extractReasoningDetailPartText($0) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            return text.isEmpty ? nil : text
        }
        if let part = value as? [String: Any] {
            return extractReasoningDetailPartText(part)
        }
        return nil
    }

    private func extractReasoningDetailPartText(_ value: [String: Any]) -> String? {
        for key in ["text", "content", "summary"] {
            if let text = value[key] as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                return text
            }
        }
        if let parts = value["parts"] as? [[String: Any]] {
            let text = parts.compactMap { extractReasoningDetailPartText($0) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            return text.isEmpty ? nil : text
        }
        return nil
    }

    // MARK: - Response rectification (output format)

    /// Rectify response using a manual config.
    public func rectifyResponseWithConfig(_ response: inout [String: Any], config: ReasoningConfig) {
        if let outputFormat = config.outputFormat {
            switch outputFormat {
            case "reasoning_content":
                transformReasoningContent(&response)
            case "reasoning_details":
                transformReasoningDetails(&response)
            default:
                break
            }
        }
    }

    /// Rectify response for a specific platform (auto-detect).
    public func rectifyResponse(_ response: inout [String: Any], platform: ReasoningPlatform) {
        switch platform {
        case .deepseek, .siliconflow, .qwen:
            transformReasoningContent(&response)
        default:
            break
        }
    }

    // MARK: - Output format transformers

    func transformReasoningContent(_ response: inout [String: Any]) {
        guard let choices = response["choices"] as? [[String: Any]] else { return }
        var newChoices: [[String: Any]] = []
        for choice in choices {
            var newChoice = choice
            if let message = choice["message"] as? [String: Any] {
                var newMessage = message
                if let reasoningContent = message["reasoning_content"] as? String {
                    let content = message["content"] as? String ?? ""
                    newMessage["content"] = "<reasoning>\(reasoningContent)</reasoning>\n\(content)"
                    newMessage.removeValue(forKey: "reasoning_content")
                }
                newChoice["message"] = newMessage
            }
            newChoices.append(newChoice)
        }
        response["choices"] = newChoices
    }

    func transformReasoningDetails(_ response: inout [String: Any]) {
        guard let choices = response["choices"] as? [[String: Any]] else { return }
        var newChoices: [[String: Any]] = []
        for choice in choices {
            var newChoice = choice
            if let message = choice["message"] as? [String: Any] {
                var newMessage = message
                if let reasoningDetails = message["reasoning_details"] as? [[String: Any]] {
                    let reasoningText = reasoningDetails.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    let content = message["content"] as? String ?? ""
                    newMessage["content"] = "<reasoning>\(reasoningText)</reasoning>\n\(content)"
                    newMessage.removeValue(forKey: "reasoning_details")
                }
                newChoice["message"] = newMessage
            }
            newChoices.append(newChoice)
        }
        response["choices"] = newChoices
    }
}

/// Supported reasoning platforms.
public enum ReasoningPlatform: String, Codable, CaseIterable, Sendable {
    case deepseek
    case openrouter
    case siliconflow
    case kimi
    case qwen
    case minimax
    case standard

    /// Detect platform from base URL.
    public static func detect(from baseURL: String?) -> ReasoningPlatform {
        guard let url = baseURL?.lowercased() else {
            return .standard
        }

        if url.contains("deepseek") { return .deepseek }
        if url.contains("openrouter") { return .openrouter }
        if url.contains("siliconflow") || url.contains("silicon-flow") { return .siliconflow }
        if url.contains("kimi") || url.contains("moonshot") { return .kimi }
        if url.contains("qwen") || url.contains("dashscope") { return .qwen }
        if url.contains("minimax") { return .minimax }

        return .standard
    }
}
