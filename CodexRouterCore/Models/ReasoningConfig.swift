import Foundation

/// Configuration for reasoning/thinking support in Codex Chat providers.
/// Matches cc-switch's CodexChatReasoningConfig exactly.
public struct ReasoningConfig: Codable, Sendable, Equatable {
    public var supportsThinking: Bool?
    public var supportsEffort: Bool?
    public var thinkingParam: String?
    public var effortParam: String?
    public var effortValueMode: String?
    public var outputFormat: String?

    public init(
        supportsThinking: Bool? = nil,
        supportsEffort: Bool? = nil,
        thinkingParam: String? = nil,
        effortParam: String? = nil,
        effortValueMode: String? = nil,
        outputFormat: String? = nil
    ) {
        self.supportsThinking = supportsThinking
        self.supportsEffort = supportsEffort
        self.thinkingParam = thinkingParam
        self.effortParam = effortParam
        self.effortValueMode = effortValueMode
        self.outputFormat = outputFormat
    }

    // MARK: - Normalization (cc-switch normalize_codex_chat_reasoning_config)

    /// Normalize: if effort is supported but thinking isn't explicitly set, imply thinking=true.
    public func normalized() -> ReasoningConfig {
        var config = self
        if config.supportsEffort == true && config.supportsThinking == nil {
            config.supportsThinking = true
        }
        return config
    }

    // MARK: - Auto-inference (cc-switch infer_codex_chat_reasoning_config)

    /// Auto-infer reasoning config from provider name, base URL, and current model.
    /// Follows cc-switch's infer_codex_chat_reasoning_config + infer_aggregator_platform_config.
    public static func infer(name: String, baseURL: String, model: String) -> ReasoningConfig? {
        let name = name.lowercased()
        let baseURL = baseURL.lowercased()
        let model = model.lowercased()

        // Platform priority: aggregator/hosting platform configs take precedence
        if let config = inferAggregatorPlatform(name: name, baseURL: baseURL) {
            return config
        }

        let haystack = "\(name) \(baseURL) \(model)"

        // DeepSeek official
        if haystack.contains("deepseek") {
            return deepseek
        }

        // StepFun: only step-3.5-flash-2603 supports reasoning effort (low/high)
        if haystack.contains("stepfun") || haystack.contains("step-3.5-flash-2603") {
            return ReasoningConfig(
                supportsThinking: true,
                supportsEffort: model.contains("2603"),
                thinkingParam: "none",
                effortParam: "reasoning_effort",
                effortValueMode: "low_high",
                outputFormat: "reasoning"
            )
        }

        // Kimi / Moonshot
        if haystack.contains("kimi") || haystack.contains("moonshot") {
            return kimi
        }

        // GLM / Zhipu / z.ai
        if haystack.contains("glm") || haystack.contains("zhipu") || haystack.contains("z.ai") {
            return glm
        }

        // Qwen / DashScope / Bailian
        if haystack.contains("qwen") || haystack.contains("dashscope") || haystack.contains("bailian") {
            return qwen
        }

        // MiniMax
        if haystack.contains("minimax") {
            return minimax
        }

        // Mimo
        if haystack.contains("mimo") {
            return mimo
        }

        return nil
    }

    /// Platform-level aggregator configs. These take priority over model-specific inference
    /// because the aggregator's reasoning interface depends on the platform, not the model vendor.
    /// cc-switch infer_aggregator_platform_config.
    private static func inferAggregatorPlatform(name: String, baseURL: String) -> ReasoningConfig? {
        let platform = "\(name) \(baseURL)"

        // OpenRouter: native reasoning:{effort} object, "openrouter" value mapping
        if platform.contains("openrouter") {
            return openrouter
        }

        // SiliconFlow: platform-wide enable_thinking
        if platform.contains("siliconflow") {
            return siliconflow
        }

        return nil
    }

    // MARK: - Pre-built presets (matching cc-switch exactly)

    /// DeepSeek official: thinking:{type} + reasoning_effort, "deepseek" effort mode.
    public static let deepseek = ReasoningConfig(
        supportsThinking: true,
        supportsEffort: true,
        thinkingParam: "thinking",
        effortParam: "reasoning_effort",
        effortValueMode: "deepseek",
        outputFormat: "reasoning_content"
    )

    /// OpenRouter: reasoning:{effort} native object, "openrouter" effort mode.
    public static let openrouter = ReasoningConfig(
        supportsThinking: false,
        supportsEffort: true,
        thinkingParam: "none",
        effortParam: "reasoning.effort",
        effortValueMode: "openrouter",
        outputFormat: "auto"
    )

    /// SiliconFlow: enable_thinking, no effort.
    public static let siliconflow = ReasoningConfig(
        supportsThinking: true,
        supportsEffort: false,
        thinkingParam: "enable_thinking",
        effortParam: "none",
        outputFormat: "reasoning_content"
    )

    /// Kimi / Moonshot: thinking:{type}, no effort.
    public static let kimi = ReasoningConfig(
        supportsThinking: true,
        supportsEffort: false,
        thinkingParam: "thinking",
        effortParam: "none",
        outputFormat: "reasoning_content"
    )

    /// GLM / Zhipu: thinking:{type}, no effort.
    public static let glm = ReasoningConfig(
        supportsThinking: true,
        supportsEffort: false,
        thinkingParam: "thinking",
        effortParam: "none",
        outputFormat: "reasoning_content"
    )

    /// Qwen / DashScope / Bailian: enable_thinking, no effort.
    public static let qwen = ReasoningConfig(
        supportsThinking: true,
        supportsEffort: false,
        thinkingParam: "enable_thinking",
        effortParam: "none",
        outputFormat: "reasoning_content"
    )

    /// MiniMax: reasoning_split, no effort, reasoning_details output.
    public static let minimax = ReasoningConfig(
        supportsThinking: true,
        supportsEffort: false,
        thinkingParam: "reasoning_split",
        effortParam: "none",
        outputFormat: "reasoning_details"
    )

    /// StepFun: thinking=none, effort via reasoning_effort (low_high mode), "reasoning" output.
    public static let stepfun = ReasoningConfig(
        supportsThinking: true,
        supportsEffort: true,
        thinkingParam: "none",
        effortParam: "reasoning_effort",
        effortValueMode: "low_high",
        outputFormat: "reasoning"
    )

    /// Mimo: thinking:{type}, no effort.
    public static let mimo = ReasoningConfig(
        supportsThinking: true,
        supportsEffort: false,
        thinkingParam: "thinking",
        effortParam: "none",
        outputFormat: "reasoning_content"
    )
}
