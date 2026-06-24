import XCTest
@testable import APIBypass

final class ParameterVisibilityCalculatorTests: XCTestCase {

    // MARK: - GPT-5.5 采样参数不可用

    func testGPT55_Temperature_Disabled() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-5.5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .temperature,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        if case .disabledWithReason(let reason) = visibility {
            XCTAssertTrue(reason.contains("不支持"))
        } else {
            XCTFail("Expected disabledWithReason, got \(visibility)")
        }
    }

    func testGPT55_TopP_Disabled() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-5.5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .topP,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        if case .disabledWithReason(_) = visibility {
            // Expected
        } else {
            XCTFail("Expected disabledWithReason, got \(visibility)")
        }
    }

    func testGPT55_ReasoningEffort_Supported() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-5.5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .reasoningEffort,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .supported)
    }

    // MARK: - DeepSeek V3 思考模式约束

    func testDeepSeekV32_ThinkingEnabled_TemperatureDisabled() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-v3.2")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .temperature,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: true
        )
        if case .disabledWithReason(let reason) = visibility {
            XCTAssertTrue(reason.contains("思考模式"))
        } else {
            XCTFail("Expected disabledWithReason, got \(visibility)")
        }
    }

    func testDeepSeekV32_ThinkingDisabled_TemperatureSupported() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-v3.2")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .temperature,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .supported)
    }

    func testDeepSeekV32_ThinkingEnabled_FrequencyPenaltyDisabled() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-v3.2")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .frequencyPenalty,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: true
        )
        if case .disabledWithReason(_) = visibility {
            // Expected
        } else {
            XCTFail("Expected disabledWithReason, got \(visibility)")
        }
    }

    // MARK: - DeepSeek R1 不支持采样参数

    func testDeepSeekR1_Temperature_AlwaysDisabled() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-r1")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .temperature,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        if case .disabledWithReason(_) = visibility {
            // Expected
        } else {
            XCTFail("Expected disabledWithReason, got \(visibility)")
        }
    }

    func testDeepSeekR1_MaxTokens_Supported() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-r1")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .maxTokens,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .supported)
    }

    // MARK: - Claude API 格式差异

    func testClaude_AnthropicAPI_TopKSupported() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-sonnet-4.5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .topK,
            modelProfile: profile,
            apiProvider: .anthropic,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .supported)
    }

    func testClaude_OpenAIAPI_TopKHidden() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-sonnet-4.5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .topK,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .hidden)  // OpenAI 格式不支持 top_k
    }

    func testClaude_AnthropicAPI_FrequencyPenaltyHidden() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-sonnet-4.5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .frequencyPenalty,
            modelProfile: profile,
            apiProvider: .anthropic,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .hidden)  // Anthropic 格式不支持
    }

    func testClaude_OpenAIAPI_FrequencyPenaltyHidden() {
        // Claude 模型本身不支持 frequencyPenalty，即使 API 格式支持也是 hidden
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-sonnet-4.5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .frequencyPenalty,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .hidden)  // 模型不支持
    }

    // MARK: - Claude Opus 4.7+ 采样参数报错

    func testClaudeOpus48_Temperature_Disabled() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-opus-4.8")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .temperature,
            modelProfile: profile,
            apiProvider: .anthropic,
            thinkingEnabled: false
        )
        if case .disabledWithReason(let reason) = visibility {
            XCTAssertTrue(reason.contains("不支持设置"))
        } else {
            XCTFail("Expected disabledWithReason, got \(visibility)")
        }
    }

    func testClaudeOpus47_TopK_Disabled() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-opus-4.7")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .topK,
            modelProfile: profile,
            apiProvider: .anthropic,
            thinkingEnabled: false
        )
        if case .disabledWithReason(_) = visibility {
            // Expected
        } else {
            XCTFail("Expected disabledWithReason, got \(visibility)")
        }
    }

    func testClaudeOpus45_Temperature_Supported() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-opus-4.5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .temperature,
            modelProfile: profile,
            apiProvider: .anthropic,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .supported)
    }

    func testClaudeOpus45_ThinkingEnabled_TemperatureDisabled() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-opus-4.5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .temperature,
            modelProfile: profile,
            apiProvider: .anthropic,
            thinkingEnabled: true
        )
        if case .disabledWithReason(_) = visibility {
            // Expected
        } else {
            XCTFail("Expected disabledWithReason, got \(visibility)")
        }
    }

    // MARK: - GLM 不支持频率惩罚

    func testGLM5_FrequencyPenalty_Disabled() {
        let profile = ModelCapabilityRegistry.findProfile(for: "glm-5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .frequencyPenalty,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        if case .disabledWithReason(let reason) = visibility {
            XCTAssertTrue(reason.contains("不支持"))
        } else {
            XCTFail("Expected disabledWithReason, got \(visibility)")
        }
    }

    func testGLM5_PresencePenalty_Disabled() {
        let profile = ModelCapabilityRegistry.findProfile(for: "glm-5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .presencePenalty,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        if case .disabledWithReason(_) = visibility {
            // Expected
        } else {
            XCTFail("Expected disabledWithReason, got \(visibility)")
        }
    }

    func testGLM5_Temperature_Supported() {
        let profile = ModelCapabilityRegistry.findProfile(for: "glm-5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .temperature,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .supported)
    }

    // MARK: - Kimi 参数固定

    func testKimiK26_Temperature_Disabled() {
        let profile = ModelCapabilityRegistry.findProfile(for: "kimi-k2.6")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .temperature,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        if case .disabledWithReason(let reason) = visibility {
            XCTAssertTrue(reason.contains("不可修改"))
        } else {
            XCTFail("Expected disabledWithReason, got \(visibility)")
        }
    }

    func testKimiK27Code_Temperature_Disabled() {
        let profile = ModelCapabilityRegistry.findProfile(for: "kimi-k2.7-code")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .temperature,
            modelProfile: profile,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        if case .disabledWithReason(_) = visibility {
            // Expected
        } else {
            XCTFail("Expected disabledWithReason, got \(visibility)")
        }
    }

    // MARK: - 未知模型使用默认能力

    func testUnknownModel_Temperature_Supported() {
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .temperature,
            modelProfile: nil,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .supported)
    }

    func testUnknownModel_MaxTokens_Supported() {
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .maxTokens,
            modelProfile: nil,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .supported)
    }

    func testUnknownModel_TopK_Hidden() {
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .topK,
            modelProfile: nil,
            apiProvider: .openai,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .hidden)
    }

    // MARK: - Responses API 参数差异

    func testResponses_MaxOutputTokens_Supported() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-5.5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .maxOutputTokens,
            modelProfile: profile,
            apiProvider: .responses,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .supported)
    }

    func testResponses_MaxTokens_Hidden() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-5.5")!
        let visibility = ParameterVisibilityCalculator.visibility(
            for: .maxTokens,
            modelProfile: profile,
            apiProvider: .responses,
            thinkingEnabled: false
        )
        XCTAssertEqual(visibility, .hidden)
    }
}

// MARK: - 思考模式可见性测试

final class ThinkingVisibilityTests: XCTestCase {

    func testO1_Thinking_Forced() {
        let profile = ModelCapabilityRegistry.findProfile(for: "o1-preview")!
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: profile,
            apiProvider: .openai
        )
        XCTAssertEqual(visibility, .visibleAndForced)
    }

    func testO3_Thinking_Forced() {
        let profile = ModelCapabilityRegistry.findProfile(for: "o3-mini")!
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: profile,
            apiProvider: .openai
        )
        XCTAssertEqual(visibility, .visibleAndForced)
    }

    func testGPT55_Thinking_Toggleable() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-5.5")!
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: profile,
            apiProvider: .openai
        )
        XCTAssertEqual(visibility, .visibleAndToggleable(defaultOn: true))
    }

    func testGPT51_Thinking_Toggleable_DefaultOff() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-5.1")!
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: profile,
            apiProvider: .openai
        )
        XCTAssertEqual(visibility, .visibleAndToggleable(defaultOn: false))
    }

    func testClaudeOpus48_Thinking_Forced() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-opus-4.8")!
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: profile,
            apiProvider: .anthropic
        )
        XCTAssertEqual(visibility, .visibleAndForced)
    }

    func testClaudeOpus45_Thinking_Toggleable() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-opus-4.5")!
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: profile,
            apiProvider: .anthropic
        )
        XCTAssertEqual(visibility, .visibleAndToggleable(defaultOn: false))
    }

    func testGPT4o_Thinking_Hidden() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-4o")!
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: profile,
            apiProvider: .openai
        )
        XCTAssertEqual(visibility, .hidden)
    }

    func testDeepSeekV32_Thinking_Toggleable() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-v3.2")!
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: profile,
            apiProvider: .openai
        )
        XCTAssertEqual(visibility, .visibleAndToggleable(defaultOn: false))
    }

    func testDeepSeekV4_Thinking_Toggleable_DefaultOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-v4")!
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: profile,
            apiProvider: .openai
        )
        XCTAssertEqual(visibility, .visibleAndToggleable(defaultOn: true))
    }

    func testDeepSeekR1_Thinking_Forced() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-r1")!
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: profile,
            apiProvider: .openai
        )
        XCTAssertEqual(visibility, .visibleAndForced)
    }

    func testQwen3_Thinking_Toggleable_DefaultOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "qwen3-8b")!
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: profile,
            apiProvider: .openai
        )
        XCTAssertEqual(visibility, .visibleAndToggleable(defaultOn: true))
    }

    func testQwQ_Thinking_Forced() {
        let profile = ModelCapabilityRegistry.findProfile(for: "qwq-32b")!
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: profile,
            apiProvider: .openai
        )
        XCTAssertEqual(visibility, .visibleAndForced)
    }

    func testGLM5_Thinking_Toggleable_DefaultOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "glm-5")!
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: profile,
            apiProvider: .openai
        )
        XCTAssertEqual(visibility, .visibleAndToggleable(defaultOn: true))
    }

    func testUnknownModel_Thinking_Hidden() {
        let visibility = ParameterVisibilityCalculator.thinkingVisibility(
            modelProfile: nil,
            apiProvider: .openai
        )
        XCTAssertEqual(visibility, .hidden)
    }
}
