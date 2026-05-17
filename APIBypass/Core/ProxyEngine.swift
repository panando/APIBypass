import Foundation

enum APIFormat {
    case openai
    case anthropic
}

enum ProxyError: Error {
    case invalidJSON
    case upstreamError(Int, Data?)
}

final class ProxyEngine {

    func transformRequest(data: Data, mapping: ModelMapping, format: APIFormat) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProxyError.invalidJSON
        }

        // Replace model name
        json["model"] = mapping.actualModel

        // Inject parameters
        injectParameters(&json, from: mapping.parameters, format: format)

        return try JSONSerialization.data(withJSONObject: json)
    }

    private func injectParameters(_ json: inout [String: Any], from params: InjectedParameters, format: APIFormat) {
        // Common parameters (OpenAI format names, also used by Anthropic)
        if let temperature = params.temperature {
            json["temperature"] = temperature
        }
        if let maxTokens = params.maxTokens {
            json["max_tokens"] = maxTokens
        }
        if let topP = params.topP {
            json["top_p"] = topP
        }
        if let frequencyPenalty = params.frequencyPenalty {
            json["frequency_penalty"] = frequencyPenalty
        }
        if let presencePenalty = params.presencePenalty {
            json["presence_penalty"] = presencePenalty
        }

        // 思考模式控制 (Anthropic + OpenAI 兼容)
        if let thinking = params.thinking {
            print("[APIBypass] 思考模式覆盖: enabled=\(thinking.enabled), budgetTokens=\(thinking.budgetTokens ?? 0)")
            switch format {
            case .anthropic:
                if thinking.enabled {
                    var thinkingDict: [String: Any] = ["type": "enabled"]
                    if let budget = thinking.budgetTokens {
                        thinkingDict["budget_tokens"] = budget
                    }
                    json["thinking"] = thinkingDict
                } else {
                    json["thinking"] = ["type": "disabled"]
                }
            case .openai:
                json["enable_thinking"] = thinking.enabled
            }
        } else {
            print("[APIBypass] 思考模式: 未配置 (使用 API 默认)")
        }

        // Custom fields - allow users to inject arbitrary JSON parameters
        if let customFields = params.customFields {
            for (key, valueString) in customFields {
                // Try to parse value as JSON (supports numbers, booleans, objects, arrays)
                if let data = valueString.data(using: .utf8),
                   let parsedValue = try? JSONSerialization.jsonObject(with: data) {
                    json[key] = parsedValue
                } else {
                    // If not valid JSON, use as plain string
                    json[key] = valueString
                }
            }
        }
    }
}
