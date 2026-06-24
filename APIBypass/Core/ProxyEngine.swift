import Foundation

enum APIFormat {
    case openai
    case anthropic
    case responses
}

enum ProxyError: Error {
    case invalidJSON
    case upstreamError(Int, Data?)
}

final class ProxyEngine {

    /// 本地模型专属参数，上游云端 API 通常不支持
    private let localModelParams: Set<String> = [
        "num_ctx",      // Ollama: 上下文窗口大小
        "num_gpu",      // Ollama: GPU 层数
        "num_thread",   // Ollama: 线程数
        "num_batch",    // Ollama: 批处理大小
        "num_keep",     // Ollama: 保持的 token 数
        "mirostat",     // Ollama: Mirostat 采样
        "mirostat_eta", // Ollama: Mirostat 学习率
        "mirostat_tau", // Ollama: Mirostat 目标熵
        "numa",         // Ollama: NUMA 支持
        "f16_kv",       // Ollama: KV cache 精度
        "logits_all",   // Ollama: 返回所有 logits
        "vocab_only",   // Ollama: 仅加载词表
        "use_mmap",     // Ollama: 内存映射
        "use_mlock",    // Ollama: 锁定内存
        "n_gpu_layers", // LM Studio: GPU 层数
        "n_ctx",        // LM Studio: 上下文大小
        "n_batch",      // LM Studio: 批处理大小
        "n_threads",    // LM Studio: 线程数
    ]

    func transformRequest(data: Data, mapping: ModelMapping, format: APIFormat) throws -> Data {
        guard let parsed = try? JSONSerialization.jsonObject(with: data),
              var json = parsed as? [String: Any] else {
            throw ProxyError.invalidJSON
        }

        // 移除本地模型专属参数（上游不支持）
        for param in localModelParams {
            json.removeValue(forKey: param)
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
        } else if format == .anthropic && json["max_tokens"] == nil {
            // Anthropic API requires max_tokens, auto-inject default
            json["max_tokens"] = 8192
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
        if let thinking = params.thinking, params.thinkingOverrideEnabled == true {
            switch format {
            case .anthropic, .responses:
                // Anthropic 上游始终用原生 thinking 协议，thinkingProtocol 字段不影响
                if thinking.enabled {
                    json["thinking"] = ["type": "enabled"]
                } else {
                    json["thinking"] = ["type": "disabled"]
                }
            case .openai:
                switch thinking.thinkingProtocol {
                case .enableThinking:
                    json["enable_thinking"] = thinking.enabled
                case .thinkingType:
                    if thinking.enabled {
                        json["thinking"] = ["type": "enabled"]
                    } else {
                        json["thinking"] = ["type": "disabled"]
                    }
                case .reasoningEffort:
                    if let effort = thinking.effort, !effort.isEmpty {
                        json["reasoning_effort"] = effort
                    }
                }
            }
        }

        // Custom fields - allow users to inject arbitrary JSON parameters
        if let customFields = params.customFields, params.customFieldsEnabled == true {
            for (key, valueString) in customFields {
                let trimmed = valueString.trimmingCharacters(in: .whitespacesAndNewlines)

                // 特殊处理布尔值
                if trimmed == "true" {
                    json[key] = true
                    continue
                } else if trimmed == "false" {
                    json[key] = false
                    continue
                }

                // 特殊处理数字
                if let intValue = Int(trimmed) {
                    json[key] = intValue
                    continue
                }
                if let doubleValue = Double(trimmed) {
                    json[key] = doubleValue
                    continue
                }

                // 尝试解析为 JSON（对象、数组、带引号的字符串）
                if let data = trimmed.data(using: .utf8),
                   let parsedValue = try? JSONSerialization.jsonObject(with: data) {
                    json[key] = parsedValue
                } else {
                    // 其他情况作为普通字符串
                    json[key] = valueString
                }
            }
        }
    }
}
