import Foundation

// MARK: - 参数定义

/// 可注入的参数类型
enum InjectedParameter: String, CaseIterable {
    case temperature
    case topP
    case topK
    case frequencyPenalty
    case presencePenalty
    case maxTokens
    case maxOutputTokens
    case thinkingType
    case budgetTokens
    case reasoningEffort
    case thinkingBudget
}

// MARK: - 思考能力类型

/// 模型的思考能力类型
enum ThinkingCapability: Equatable {
    /// 强制思考，不可关闭
    case alwaysOn
    /// 可选思考，带默认状态
    case optional(defaultOn: Bool)
    /// 自适应思考（Claude 4.6+）
    case adaptive
    /// 不支持思考
    case notSupported
}

// MARK: - 参数可见性

/// 参数在 UI 中的可见性状态
enum ParameterVisibility: Equatable {
    /// 正常可用
    case supported
    /// 显示但禁用，附带原因
    case disabledWithReason(String)
    /// 完全隐藏
    case hidden
}

/// 思考模式在 UI 中的可见性状态
enum ThinkingVisibility: Equatable {
    /// 完全隐藏
    case hidden
    /// 显示但不可切换（强制开启）
    case visibleAndForced
    /// 显示且可切换
    case visibleAndToggleable(defaultOn: Bool)
}

// MARK: - 参数约束

/// 参数约束条件
struct ParameterConstraint: Equatable {
    let parameter: InjectedParameter
    let condition: ConstraintCondition
    let reason: String
}

/// 约束触发条件
enum ConstraintCondition: Equatable {
    /// 思考开启时触发
    case whenThinkingEnabled
    /// 思考关闭时触发
    case whenThinkingDisabled
    /// 始终触发
    case always
    /// 参数值固定
    case fixedValue(Double)
}

// MARK: - 模型能力档案

/// 模型原始能力档案（不考虑 API 格式限制）
struct ModelCapabilityProfile: Equatable {
    let id: String
    let patterns: [String]
    let thinkingCapability: ThinkingCapability
    let samplingEffectiveInThinking: Bool
    let nativeParameters: Set<InjectedParameter>
    let constraints: [ParameterConstraint]

    /// 匹配模型名称（不区分大小写）
    func matches(_ modelName: String) -> Bool {
        let lowerModelName = modelName.lowercased()
        for pattern in patterns {
            if lowerModelName.hasPrefix(pattern.lowercased()) {
                return true
            }
        }
        return false
    }
}

// MARK: - 模型能力档案注册表

enum ModelCapabilityRegistry {

    /// 所有模型能力档案
    static let allProfiles: [ModelCapabilityProfile] = [
        // MARK: OpenAI 系列

        .init(
            id: "gpt-5.5",
            patterns: ["gpt-5.5"],
            thinkingCapability: .optional(defaultOn: true),
            samplingEffectiveInThinking: false,
            nativeParameters: [.maxTokens, .maxOutputTokens, .reasoningEffort],
            constraints: [
                .init(parameter: .temperature, condition: .always, reason: "GPT-5.5 不支持 temperature 参数"),
                .init(parameter: .topP, condition: .always, reason: "GPT-5.5 不支持 top_p 参数"),
                .init(parameter: .frequencyPenalty, condition: .always, reason: "GPT-5.5 不支持 frequency_penalty 参数"),
                .init(parameter: .presencePenalty, condition: .always, reason: "GPT-5.5 不支持 presence_penalty 参数")
            ]
        ),

        .init(
            id: "gpt-5.4",
            patterns: ["gpt-5.4"],
            thinkingCapability: .optional(defaultOn: false),
            samplingEffectiveInThinking: false,
            nativeParameters: [.maxTokens, .maxOutputTokens, .reasoningEffort],
            constraints: [
                .init(parameter: .temperature, condition: .always, reason: "GPT-5.4 不支持 temperature 参数"),
                .init(parameter: .topP, condition: .always, reason: "GPT-5.4 不支持 top_p 参数"),
                .init(parameter: .frequencyPenalty, condition: .always, reason: "GPT-5.4 不支持 frequency_penalty 参数"),
                .init(parameter: .presencePenalty, condition: .always, reason: "GPT-5.4 不支持 presence_penalty 参数")
            ]
        ),

        .init(
            id: "gpt-5.1",
            patterns: ["gpt-5.1", "gpt-5.2", "gpt-5.3"],
            thinkingCapability: .optional(defaultOn: false),
            samplingEffectiveInThinking: false,
            nativeParameters: [.maxTokens, .maxOutputTokens, .reasoningEffort],
            constraints: [
                .init(parameter: .temperature, condition: .always, reason: "该模型不支持 temperature 参数"),
                .init(parameter: .topP, condition: .always, reason: "该模型不支持 top_p 参数"),
                .init(parameter: .frequencyPenalty, condition: .always, reason: "该模型不支持 frequency_penalty 参数"),
                .init(parameter: .presencePenalty, condition: .always, reason: "该模型不支持 presence_penalty 参数")
            ]
        ),

        .init(
            id: "gpt-5",
            patterns: ["gpt-5-"],
            thinkingCapability: .optional(defaultOn: true),
            samplingEffectiveInThinking: false,
            nativeParameters: [.maxTokens, .maxOutputTokens, .reasoningEffort],
            constraints: [
                .init(parameter: .temperature, condition: .always, reason: "GPT-5 不支持 temperature 参数"),
                .init(parameter: .topP, condition: .always, reason: "GPT-5 不支持 top_p 参数"),
                .init(parameter: .frequencyPenalty, condition: .always, reason: "GPT-5 不支持 frequency_penalty 参数"),
                .init(parameter: .presencePenalty, condition: .always, reason: "GPT-5 不支持 presence_penalty 参数")
            ]
        ),

        .init(
            id: "o-series",
            patterns: ["o1-", "o1_", "o3-", "o3_", "o4-"],
            thinkingCapability: .alwaysOn,
            samplingEffectiveInThinking: false,
            nativeParameters: [.maxTokens, .maxOutputTokens, .reasoningEffort],
            constraints: [
                .init(parameter: .temperature, condition: .always, reason: "推理模型不支持 temperature 参数"),
                .init(parameter: .topP, condition: .always, reason: "推理模型不支持 top_p 参数"),
                .init(parameter: .frequencyPenalty, condition: .always, reason: "推理模型不支持 frequency_penalty 参数"),
                .init(parameter: .presencePenalty, condition: .always, reason: "推理模型不支持 presence_penalty 参数")
            ]
        ),

        .init(
            id: "gpt-4o",
            patterns: ["gpt-4o", "gpt-4-turbo", "gpt-4-"],
            thinkingCapability: .notSupported,
            samplingEffectiveInThinking: true,
            nativeParameters: [.temperature, .topP, .maxTokens, .frequencyPenalty, .presencePenalty],
            constraints: []
        ),

        // MARK: DeepSeek 系列

        .init(
            id: "deepseek-v4",
            patterns: ["deepseek-v4"],
            thinkingCapability: .optional(defaultOn: true),
            samplingEffectiveInThinking: false,
            nativeParameters: [.maxTokens, .reasoningEffort],
            constraints: [
                .init(parameter: .temperature, condition: .whenThinkingEnabled, reason: "思考模式下 temperature 参数无效"),
                .init(parameter: .topP, condition: .whenThinkingEnabled, reason: "思考模式下 top_p 参数无效"),
                .init(parameter: .frequencyPenalty, condition: .whenThinkingEnabled, reason: "思考模式下 frequency_penalty 参数无效"),
                .init(parameter: .presencePenalty, condition: .whenThinkingEnabled, reason: "思考模式下 presence_penalty 参数无效")
            ]
        ),

        .init(
            id: "deepseek-v3-hybrid",
            patterns: ["deepseek-v3.1", "deepseek-v3.2"],
            thinkingCapability: .optional(defaultOn: false),
            samplingEffectiveInThinking: false,
            nativeParameters: [.temperature, .topP, .maxTokens, .frequencyPenalty, .presencePenalty, .thinkingType],
            constraints: [
                .init(parameter: .temperature, condition: .whenThinkingEnabled, reason: "思考模式下 temperature 参数无效"),
                .init(parameter: .topP, condition: .whenThinkingEnabled, reason: "思考模式下 top_p 参数无效"),
                .init(parameter: .frequencyPenalty, condition: .whenThinkingEnabled, reason: "思考模式下 frequency_penalty 参数无效"),
                .init(parameter: .presencePenalty, condition: .whenThinkingEnabled, reason: "思考模式下 presence_penalty 参数无效")
            ]
        ),

        .init(
            id: "deepseek-r1",
            patterns: ["deepseek-r1"],
            thinkingCapability: .alwaysOn,
            samplingEffectiveInThinking: false,
            nativeParameters: [.maxTokens],
            constraints: [
                .init(parameter: .temperature, condition: .always, reason: "DeepSeek-R1 不支持采样参数"),
                .init(parameter: .topP, condition: .always, reason: "DeepSeek-R1 不支持采样参数"),
                .init(parameter: .frequencyPenalty, condition: .always, reason: "DeepSeek-R1 不支持采样参数"),
                .init(parameter: .presencePenalty, condition: .always, reason: "DeepSeek-R1 不支持采样参数")
            ]
        ),

        .init(
            id: "deepseek-v3",
            patterns: ["deepseek-v3"],
            thinkingCapability: .notSupported,
            samplingEffectiveInThinking: true,
            nativeParameters: [.temperature, .topP, .maxTokens, .frequencyPenalty, .presencePenalty],
            constraints: []
        ),

        .init(
            id: "deepseek",
            patterns: ["deepseek-"],
            thinkingCapability: .notSupported,
            samplingEffectiveInThinking: true,
            nativeParameters: [.temperature, .topP, .maxTokens, .frequencyPenalty, .presencePenalty],
            constraints: []
        ),

        // MARK: Qwen 系列

        .init(
            id: "qwen3",
            patterns: ["qwen3", "qwen3-"],
            thinkingCapability: .optional(defaultOn: true),
            samplingEffectiveInThinking: true,
            nativeParameters: [.temperature, .topP, .maxTokens, .frequencyPenalty, .presencePenalty, .thinkingType, .thinkingBudget],
            constraints: []
        ),

        .init(
            id: "qwq",
            patterns: ["qwq"],
            thinkingCapability: .alwaysOn,
            samplingEffectiveInThinking: false,
            nativeParameters: [.maxTokens],
            constraints: [
                .init(parameter: .temperature, condition: .always, reason: "QwQ 不支持采样参数"),
                .init(parameter: .topP, condition: .always, reason: "QwQ 不支持采样参数")
            ]
        ),

        .init(
            id: "qwen",
            patterns: ["qwen-"],
            thinkingCapability: .notSupported,
            samplingEffectiveInThinking: true,
            nativeParameters: [.temperature, .topP, .maxTokens, .frequencyPenalty, .presencePenalty],
            constraints: []
        ),

        // MARK: GLM 系列

        .init(
            id: "glm-5",
            patterns: ["glm-5"],
            thinkingCapability: .optional(defaultOn: true),
            samplingEffectiveInThinking: true,
            nativeParameters: [.temperature, .topP, .maxTokens, .thinkingType],
            constraints: [
                .init(parameter: .frequencyPenalty, condition: .always, reason: "GLM 系列不支持 frequency_penalty 参数"),
                .init(parameter: .presencePenalty, condition: .always, reason: "GLM 系列不支持 presence_penalty 参数")
            ]
        ),

        .init(
            id: "glm-4.5",
            patterns: ["glm-4.5", "glm-4.6", "glm-4.7"],
            thinkingCapability: .optional(defaultOn: true),
            samplingEffectiveInThinking: true,
            nativeParameters: [.temperature, .topP, .maxTokens, .thinkingType],
            constraints: [
                .init(parameter: .frequencyPenalty, condition: .always, reason: "GLM 系列不支持 frequency_penalty 参数"),
                .init(parameter: .presencePenalty, condition: .always, reason: "GLM 系列不支持 presence_penalty 参数")
            ]
        ),

        .init(
            id: "glm-4",
            patterns: ["glm-4"],
            thinkingCapability: .notSupported,
            samplingEffectiveInThinking: true,
            nativeParameters: [.temperature, .topP, .maxTokens],
            constraints: [
                .init(parameter: .frequencyPenalty, condition: .always, reason: "GLM 系列不支持 frequency_penalty 参数"),
                .init(parameter: .presencePenalty, condition: .always, reason: "GLM 系列不支持 presence_penalty 参数")
            ]
        ),

        // MARK: Kimi 系列

        .init(
            id: "kimi-k2.7-code",
            patterns: ["kimi-k2.7-code"],
            thinkingCapability: .alwaysOn,
            samplingEffectiveInThinking: false,
            nativeParameters: [.maxTokens],
            constraints: [
                .init(parameter: .temperature, condition: .always, reason: "Kimi K2.7 Code 参数固定为 1.0"),
                .init(parameter: .topP, condition: .always, reason: "Kimi K2.7 Code 参数固定为 0.95")
            ]
        ),

        .init(
            id: "kimi-k2.6",
            patterns: ["kimi-k2.6", "kimi-k2.5"],
            thinkingCapability: .optional(defaultOn: false),
            samplingEffectiveInThinking: false,
            nativeParameters: [.maxTokens, .thinkingType],
            constraints: [
                .init(parameter: .temperature, condition: .always, reason: "Kimi 参数固定为 1.0"),
                .init(parameter: .topP, condition: .always, reason: "Kimi 参数固定为 0.95"),
                .init(parameter: .frequencyPenalty, condition: .always, reason: "Kimi 参数固定为 0"),
                .init(parameter: .presencePenalty, condition: .always, reason: "Kimi 参数固定为 0")
            ]
        ),

        // MARK: Doubao 系列

        .init(
            id: "doubao-seed",
            patterns: ["doubao-seed", "doubao-1.5-thinking"],
            thinkingCapability: .optional(defaultOn: true),
            samplingEffectiveInThinking: true,
            nativeParameters: [.temperature, .topP, .maxTokens, .thinkingType],
            constraints: [
                .init(parameter: .frequencyPenalty, condition: .always, reason: "Doubao 思考模型不支持 frequency_penalty 参数"),
                .init(parameter: .presencePenalty, condition: .always, reason: "Doubao 思考模型不支持 presence_penalty 参数")
            ]
        ),

        .init(
            id: "doubao",
            patterns: ["doubao-"],
            thinkingCapability: .notSupported,
            samplingEffectiveInThinking: true,
            nativeParameters: [.temperature, .topP, .maxTokens, .frequencyPenalty, .presencePenalty],
            constraints: []
        ),

        // MARK: MiniMax 系列

        .init(
            id: "minimax-m3",
            patterns: ["minimax-m3"],
            thinkingCapability: .optional(defaultOn: false),
            samplingEffectiveInThinking: true,
            nativeParameters: [.temperature, .topP, .maxTokens, .thinkingType],
            constraints: [
                .init(parameter: .frequencyPenalty, condition: .always, reason: "MiniMax 不支持 frequency_penalty 参数"),
                .init(parameter: .presencePenalty, condition: .always, reason: "MiniMax 不支持 presence_penalty 参数")
            ]
        ),

        .init(
            id: "minimax-m2",
            patterns: ["minimax-m2"],
            thinkingCapability: .alwaysOn,
            samplingEffectiveInThinking: false,
            nativeParameters: [.temperature, .topP, .maxTokens],
            constraints: [
                .init(parameter: .frequencyPenalty, condition: .always, reason: "MiniMax 不支持 frequency_penalty 参数"),
                .init(parameter: .presencePenalty, condition: .always, reason: "MiniMax 不支持 presence_penalty 参数")
            ]
        ),

        // MARK: Claude 系列

        .init(
            id: "claude-4.8",
            patterns: ["claude-opus-4.8", "claude-opus-4.7"],
            thinkingCapability: .adaptive,
            samplingEffectiveInThinking: false,
            nativeParameters: [.maxTokens, .thinkingType],
            constraints: [
                .init(parameter: .temperature, condition: .always, reason: "Claude Opus 4.7+ 不支持设置 temperature"),
                .init(parameter: .topP, condition: .always, reason: "Claude Opus 4.7+ 不支持设置 top_p"),
                .init(parameter: .topK, condition: .always, reason: "Claude Opus 4.7+ 不支持设置 top_k")
            ]
        ),

        .init(
            id: "claude-4.6",
            patterns: ["claude-opus-4.6", "claude-sonnet-4.6"],
            thinkingCapability: .adaptive,
            samplingEffectiveInThinking: false,
            nativeParameters: [.maxTokens, .thinkingType],
            constraints: [
                .init(parameter: .temperature, condition: .always, reason: "Claude 4.6 不支持设置 temperature"),
                .init(parameter: .topP, condition: .always, reason: "Claude 4.6 不支持设置 top_p"),
                .init(parameter: .topK, condition: .always, reason: "Claude 4.6 不支持设置 top_k")
            ]
        ),

        .init(
            id: "claude-4.5",
            patterns: ["claude-opus-4.5", "claude-sonnet-4.5", "claude-haiku-4.5"],
            thinkingCapability: .optional(defaultOn: false),
            samplingEffectiveInThinking: true,
            nativeParameters: [.temperature, .topP, .topK, .maxTokens, .thinkingType, .budgetTokens],
            constraints: [
                .init(parameter: .temperature, condition: .whenThinkingEnabled, reason: "思考模式下 temperature 必须为 1.0")
            ]
        ),

        .init(
            id: "claude",
            patterns: ["claude-"],
            thinkingCapability: .optional(defaultOn: false),
            samplingEffectiveInThinking: true,
            nativeParameters: [.temperature, .topP, .topK, .maxTokens, .thinkingType, .budgetTokens],
            constraints: [
                .init(parameter: .temperature, condition: .whenThinkingEnabled, reason: "思考模式下 temperature 必须为 1.0")
            ]
        ),
    ]

    /// 默认能力档案（用于未知模型）
    static let defaultProfile = ModelCapabilityProfile(
        id: "default",
        patterns: [],
        thinkingCapability: .notSupported,
        samplingEffectiveInThinking: true,
        nativeParameters: [.temperature, .topP, .maxTokens, .frequencyPenalty, .presencePenalty],
        constraints: []
    )

    /// 根据模型名称查找匹配的档案
    static func findProfile(for modelName: String) -> ModelCapabilityProfile? {
        // 按优先级匹配（更具体的模式优先，靠前的 profile 优先）
        for profile in allProfiles {
            if profile.matches(modelName) {
                return profile
            }
        }
        return nil
    }
}

// MARK: - 参数可见性计算器

enum ParameterVisibilityCalculator {

    /// 计算最终参数可见性
    /// - Parameters:
    ///   - parameter: 要检查的参数
    ///   - modelProfile: 模型能力档案（nil 使用默认）
    ///   - apiProvider: API 格式
    ///   - thinkingEnabled: 思考模式是否开启
    /// - Returns: 参数可见性状态
    static func visibility(
        for parameter: InjectedParameter,
        modelProfile: ModelCapabilityProfile?,
        apiProvider: APIProvider,
        thinkingEnabled: Bool
    ) -> ParameterVisibility {

        // 1. 获取模型能力（未知模型使用默认）
        let profile = modelProfile ?? ModelCapabilityRegistry.defaultProfile

        // 2. 检查 API 格式是否支持传输该参数
        guard apiProvider.transportableParameters.contains(parameter) else {
            return .hidden
        }

        // 3. 先检查约束条件（约束表示参数存在但受限）
        for constraint in profile.constraints {
            guard constraint.parameter == parameter else { continue }

            switch constraint.condition {
            case .whenThinkingEnabled:
                if thinkingEnabled {
                    return .disabledWithReason(constraint.reason)
                }
            case .whenThinkingDisabled:
                if !thinkingEnabled {
                    return .disabledWithReason(constraint.reason)
                }
            case .always:
                return .disabledWithReason(constraint.reason)
            case .fixedValue:
                return .disabledWithReason(constraint.reason)
            }
        }

        // 4. 检查模型是否支持该参数
        guard profile.nativeParameters.contains(parameter) else {
            return .hidden
        }

        return .supported
    }

    /// 计算思考模式可见性
    /// - Parameters:
    ///   - modelProfile: 模型能力档案（nil 使用默认）
    ///   - apiProvider: API 格式
    /// - Returns: 思考模式可见性状态
    static func thinkingVisibility(
        modelProfile: ModelCapabilityProfile?,
        apiProvider: APIProvider
    ) -> ThinkingVisibility {

        let profile = modelProfile ?? ModelCapabilityRegistry.defaultProfile

        switch profile.thinkingCapability {
        case .alwaysOn:
            return .visibleAndForced

        case .optional(let defaultOn):
            // 检查 API 格式是否支持 thinking 参数
            let supported = apiProvider.transportableParameters.contains(.thinkingType) ||
                           apiProvider == .openai || apiProvider == .responses
            return supported ? .visibleAndToggleable(defaultOn: defaultOn) : .hidden

        case .adaptive:
            return .visibleAndForced

        case .notSupported:
            return .hidden
        }
    }
}
