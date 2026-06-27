import XCTest
@testable import CodexRouterCore

final class ParamErrorRetryTests: XCTestCase {

    // MARK: - Test 1: 检测可移除参数错误

    /// 当错误明确指出某个参数不支持时，应返回移除该参数的动作
    func testParseParamError_withRemovableParam_returnsRemoveAction() {
        let errorJSON = """
        {
            "error": {
                "code": "InvalidParameter",
                "type": "BadRequest",
                "message": "The parameter `reasoning` is not supported by current model.",
                "param": "reasoning"
            }
        }
        """.data(using: .utf8)!

        let action = parseParamErrorAction(status: 400, errorBody: errorJSON)

        XCTAssertEqual(action, .remove("reasoning"))
    }

    // MARK: - Test 2: 检测可替换参数错误

    /// 当 max_tokens 不支持时，应返回替换为 max_completion_tokens 的动作
    func testParseParamError_withReplaceableParam_returnsReplaceAction() {
        let errorJSON = """
        {
            "error": {
                "code": "InvalidParameter",
                "message": "Unrecognized request argument: max_tokens",
                "param": "max_tokens"
            }
        }
        """.data(using: .utf8)!

        let action = parseParamErrorAction(status: 400, errorBody: errorJSON)

        XCTAssertEqual(action, .replace("max_tokens", "max_completion_tokens"))
    }

    // MARK: - Test 3: 通过消息解析参数名

    /// 当没有 param 字段，但消息中包含参数名和 "not supported" 时，应返回移除动作
    func testParseParamError_withMessageOnly_returnsRemoveAction() {
        let errorJSON = """
        {
            "error": {
                "code": "InvalidParameter",
                "message": "The parameter `reasoning` is not supported by current model."
            }
        }
        """.data(using: .utf8)!

        let action = parseParamErrorAction(status: 400, errorBody: errorJSON)

        XCTAssertEqual(action, .remove("reasoning"))
    }

    // MARK: - Test 4: 非 400 错误不重试

    /// 非 400 错误不应触发重试
    func testParseParamError_withNon400Status_returnsNil() {
        let errorJSON = """
        {
            "error": {
                "code": "InvalidParameter",
                "param": "reasoning"
            }
        }
        """.data(using: .utf8)!

        let action = parseParamErrorAction(status: 401, errorBody: errorJSON)

        XCTAssertNil(action)
    }

    // MARK: - Test 5: 未知参数不重试

    /// 未知的参数不应触发重试
    func testParseParamError_withUnknownParam_returnsNil() {
        let errorJSON = """
        {
            "error": {
                "code": "InvalidParameter",
                "message": "The parameter `unknown_param` is not supported.",
                "param": "unknown_param"
            }
        }
        """.data(using: .utf8)!

        let action = parseParamErrorAction(status: 400, errorBody: errorJSON)

        XCTAssertNil(action)
    }

    // MARK: - Test 6: 参数值错误不重试

    /// 参数值错误（如 temperature=999）不应触发重试
    func testParseParamError_withInvalidValue_returnsNil() {
        let errorJSON = """
        {
            "error": {
                "code": "InvalidParameter",
                "message": "Invalid value for temperature: must be between 0 and 2",
                "param": "temperature"
            }
        }
        """.data(using: .utf8)!

        let action = parseParamErrorAction(status: 400, errorBody: errorJSON)

        XCTAssertNil(action)
    }
}
