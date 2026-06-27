import Foundation

/// 参数错误处理动作
public enum ParamErrorAction: Equatable {
    case remove(String)           // 移除参数
    case replace(String, String)  // 替换参数 (old, new)
}

/// 可安全移除的参数列表
public let removableParams = [
    "reasoning", "thinking", "temperature", "top_p",
    "frequency_penalty", "presence_penalty", "stop", "response_format"
]

/// 参数替换映射
public let paramReplacements = [
    "max_tokens": "max_completion_tokens",
    "max_completion_tokens": "max_tokens"
]

/// 解析错误响应，判断是否可以通过移除/替换参数来重试
/// - Parameters:
///   - status: HTTP 状态码
///   - errorBody: 错误响应体
/// - Returns: 可重试时返回动作，否则返回 nil
public func parseParamErrorAction(status: Int, errorBody: Data) -> ParamErrorAction? {
    guard status == 400 else { return nil }

    guard let json = try? JSONSerialization.jsonObject(with: errorBody) as? [String: Any],
          let error = json["error"] as? [String: Any] else {
        return nil
    }

    let message = error["message"] as? String
    let lowerMessage = message?.lowercased() ?? ""

    // 检查消息是否表明是"参数不支持"类型的错误
    let unsupportedIndicators = ["not supported", "unsupported", "unrecognized", "invalid parameter"]
    let isUnsupportedError = unsupportedIndicators.contains { lowerMessage.contains($0) }
    guard isUnsupportedError else { return nil }

    // 检查 error.param 字段
    if let param = error["param"] as? String {
        // 检查是否是可移除的参数
        if removableParams.contains(param) {
            return .remove(param)
        }
        // 检查是否是可替换的参数
        if let replacement = paramReplacements[param] {
            return .replace(param, replacement)
        }
        // 未知参数不重试
        return nil
    }

    // 没有 param 字段时，尝试从 message 中解析参数名
    // 在消息中查找可移除参数的名字
    for param in removableParams {
        if lowerMessage.contains(param) {
            return .remove(param)
        }
    }
    // 在消息中查找可替换参数的名字
    for (param, replacement) in paramReplacements {
        if lowerMessage.contains(param) {
            return .replace(param, replacement)
        }
    }

    return nil
}
