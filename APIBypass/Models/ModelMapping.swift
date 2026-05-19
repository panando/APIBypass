import Foundation

struct ThinkingConfig: Codable, Equatable {
    let enabled: Bool
    let budgetTokens: Int?

    init(enabled: Bool, budgetTokens: Int? = nil) {
        self.enabled = enabled
        self.budgetTokens = budgetTokens
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
        customFieldsEnabled: Bool? = nil
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
    }

    static let empty = InjectedParameters()
}

struct ModelMapping: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var incomingModel: String
    var actualModel: String
    var apiProvider: APIProvider
    var baseURL: URL
    var parameters: InjectedParameters
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        incomingModel: String,
        actualModel: String,
        apiProvider: APIProvider,
        baseURL: URL,
        parameters: InjectedParameters,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.incomingModel = incomingModel
        self.actualModel = actualModel
        self.apiProvider = apiProvider
        self.baseURL = baseURL
        self.parameters = parameters
        self.isEnabled = isEnabled
    }

    func matches(model: String) -> Bool {
        isEnabled && incomingModel == model
    }
}
