import Foundation

struct ThinkingConfig: Codable, Equatable {
    enum `Protocol`: String, Codable, CaseIterable {
        case enable_thinking      // GLM / Qwen / Kimi / Ark
        case reasoning_effort     // OpenAI o-series
        case anthropic_native     // Anthropic 兼容上游
        case none                 // 不发字段（模型自身即开关）

        var displayName: String {
            switch self {
            case .enable_thinking: return "enable_thinking"
            case .reasoning_effort: return "reasoning_effort"
            case .anthropic_native: return "thinking (Anthropic)"
            case .none: return "none"
            }
        }
    }

    let enabled: Bool
    let budgetTokens: Int?
    let `protocol`: `Protocol`
    let effort: String?

    init(enabled: Bool,
         budgetTokens: Int? = nil,
         `protocol`: `Protocol` = .enable_thinking,
         effort: String? = nil) {
        self.enabled = enabled
        self.budgetTokens = budgetTokens
        self.`protocol` = `protocol`
        self.effort = effort
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, budgetTokens, `protocol`, effort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        budgetTokens = try c.decodeIfPresent(Int.self, forKey: .budgetTokens)
        `protocol` = try c.decodeIfPresent(`Protocol`.self, forKey: .protocol) ?? .enable_thinking
        effort = try c.decodeIfPresent(String.self, forKey: .effort)
    }
}

struct InjectedParameters: Codable, Equatable {
    let temperature: Double?
    let maxTokens: Int?
    let topP: Double?
    let frequencyPenalty: Double?
    let presencePenalty: Double?
    let timeout: TimeInterval?
    let retryCount: Int?
    let customHeaders: [String: String]?
    let thinking: ThinkingConfig?
    let thinkingOverrideEnabled: Bool?
    let customFields: [String: String]?
    let customFieldsEnabled: Bool?
    let rectifierEnabled: Bool?

    init(
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        timeout: TimeInterval? = nil,
        retryCount: Int? = nil,
        customHeaders: [String: String]? = nil,
        thinking: ThinkingConfig? = nil,
        thinkingOverrideEnabled: Bool? = nil,
        customFields: [String: String]? = nil,
        customFieldsEnabled: Bool? = nil,
        rectifierEnabled: Bool? = nil
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.timeout = timeout
        self.retryCount = retryCount
        self.customHeaders = customHeaders
        self.thinking = thinking
        self.thinkingOverrideEnabled = thinkingOverrideEnabled
        self.customFields = customFields
        self.customFieldsEnabled = customFieldsEnabled
        self.rectifierEnabled = rectifierEnabled
    }

    static let empty = InjectedParameters()
}

struct ModelMapping: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var incomingModel: String
    var actualModel: String
    var providerConfigId: UUID
    var parameters: InjectedParameters
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        incomingModel: String,
        actualModel: String,
        providerConfigId: UUID,
        parameters: InjectedParameters,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.incomingModel = incomingModel
        self.actualModel = actualModel
        self.providerConfigId = providerConfigId
        self.parameters = parameters
        self.isEnabled = isEnabled
    }

    func matches(model: String) -> Bool {
        guard isEnabled else { return false }
        if incomingModel == model { return true }
        let stripped = model.replacingOccurrences(of: #"\[\d+[km]\]"#, with: "", options: .regularExpression)
        return incomingModel == stripped
    }
}

// `ThinkingConfig.Protocol` cannot be referenced by its declared name from outside the
// type: Swift parses `ThinkingConfig.Protocol` as the protocol-metatype accessor
// (`T.Protocol`), not as member access on the nested enum. The alias below exposes the
// enum under a name external callers can actually use.
extension ThinkingConfig {
    typealias Proto = `Protocol`
}

extension ThinkingConfig.`Protocol` {
    /// Auto-detect which thinking protocol an upstream expects, based on its baseURL
    /// and the model name. Used when a mapping has no explicit protocol configured.
    static func infer(baseURL: String, model: String) -> ThinkingConfig.`Protocol` {
        let lower = baseURL.lowercased()
        let m = model.lowercased()

        if lower.contains("anthropic") { return .anthropic_native }
        if m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") { return .reasoning_effort }
        if m.hasPrefix("deepseek-r") { return .none }
        if lower.contains("bigmodel") || lower.contains("z.ai")
            || lower.contains("moonshot") || lower.contains("aliyuncs")
            || lower.contains("volces") || lower.contains("ark.cn-beijing") {
            return .enable_thinking
        }
        return .enable_thinking
    }
}
