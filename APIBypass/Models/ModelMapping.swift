import Foundation

struct ThinkingConfig: Codable, Equatable {
    enum ThinkingProtocol: String, Codable, CaseIterable {
        case enable_thinking      // Qwen3 系列（DashScope）
        case anthropic_native     // thinking.type: Anthropic / GLM / Kimi / DeepSeek / Doubao
        case none                 // 不发开关字段；o 系列可附 reasoning_effort 程度

        var displayName: String {
            switch self {
            case .enable_thinking: return "enable_thinking"
            case .anthropic_native: return "thinking.type"
            case .none: return "none"
            }
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            switch raw {
            case "enable_thinking": self = .enable_thinking
            case "anthropic_native": self = .anthropic_native
            case "none": self = .none
            case "reasoning_effort": self = .none
            default: self = .enable_thinking
            }
        }
    }

    let enabled: Bool
    let budgetTokens: Int?
    let thinkingProtocol: ThinkingProtocol
    let effort: String?

    init(enabled: Bool,
         budgetTokens: Int? = nil,
         thinkingProtocol: ThinkingProtocol = .enable_thinking,
         effort: String? = nil) {
        self.enabled = enabled
        self.budgetTokens = budgetTokens
        self.thinkingProtocol = thinkingProtocol
        self.effort = effort
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, budgetTokens
        case thinkingProtocol = "protocol"
        case effort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        budgetTokens = try c.decodeIfPresent(Int.self, forKey: .budgetTokens)
        thinkingProtocol = try c.decodeIfPresent(ThinkingProtocol.self, forKey: .thinkingProtocol) ?? .enable_thinking
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

extension ThinkingConfig.ThinkingProtocol {
    /// Auto-detect which thinking protocol an upstream expects, based on its baseURL
    /// and the model name. Used when a mapping has no explicit protocol configured.
    static func infer(baseURL: String, model: String) -> ThinkingConfig.ThinkingProtocol {
        let lower = baseURL.lowercased()
        let m = model.lowercased()

        if lower.contains("anthropic") { return .anthropic_native }
        if m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") { return .none }
        if m.hasPrefix("deepseek-r") { return .none }
        if lower.contains("aliyuncs") { return .enable_thinking }
        if lower.contains("bigmodel") || lower.contains("z.ai")
            || lower.contains("moonshot")
            || lower.contains("volces") || lower.contains("ark.cn-beijing") {
            return .anthropic_native
        }
        return .enable_thinking
    }
}
