import XCTest
@testable import APIBypass

final class ModelCapabilityProfileTests: XCTestCase {

    // MARK: - OpenAI 系列

    func testGPT55_OptionalThinking_DefaultOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-5.5-2026-04-23")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: true))
    }

    func testGPT54_OptionalThinking_DefaultOff() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-5.4")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: false))
    }

    func testGPT51_OptionalThinking_DefaultOff() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-5.1-2025-11-13")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: false))
    }

    func testO1_AlwaysOnThinking() {
        let profile = ModelCapabilityRegistry.findProfile(for: "o1-preview")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .alwaysOn)
    }

    func testO3_AlwaysOnThinking() {
        let profile = ModelCapabilityRegistry.findProfile(for: "o3-mini")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .alwaysOn)
    }

    func testO4_AlwaysOnThinking() {
        let profile = ModelCapabilityRegistry.findProfile(for: "o4-mini")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .alwaysOn)
    }

    func testGPT4o_NotSupported() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-4o-2024-11-20")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .notSupported)
    }

    func testGPT4Turbo_NotSupported() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-4-turbo-2024-04-09")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .notSupported)
    }

    // MARK: - DeepSeek 系列

    func testDeepSeekV4_OptionalThinking_DefaultOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-v4-pro")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: true))
    }

    func testDeepSeekV32_OptionalThinking_DefaultOff() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-v3.2")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: false))
    }

    func testDeepSeekV31_OptionalThinking_DefaultOff() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-v3.1")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: false))
    }

    func testDeepSeekR1_AlwaysOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-r1")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .alwaysOn)
    }

    func testDeepSeekV3_NotSupported() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-v3")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .notSupported)
    }

    // MARK: - Qwen 系列

    func testQwen3_OptionalThinking_DefaultOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "qwen3-8b")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: true))
    }

    func testQwQ_AlwaysOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "qwq-32b")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .alwaysOn)
    }

    func testQwen_NotSupported() {
        let profile = ModelCapabilityRegistry.findProfile(for: "qwen-plus")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .notSupported)
    }

    // MARK: - GLM 系列

    func testGLM5_OptionalThinking_DefaultOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "glm-5")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: true))
    }

    func testGLM45_OptionalThinking_DefaultOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "glm-4.5")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: true))
    }

    func testGLM4_NotSupported() {
        let profile = ModelCapabilityRegistry.findProfile(for: "glm-4")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .notSupported)
    }

    // MARK: - Claude 系列

    func testClaudeOpus48_Adaptive() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-opus-4.8-20250514")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .adaptive)
    }

    func testClaudeOpus47_Adaptive() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-opus-4.7")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .adaptive)
    }

    func testClaudeOpus46_Adaptive() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-opus-4.6-20250514")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .adaptive)
    }

    func testClaudeSonnet46_Adaptive() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-sonnet-4.6")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .adaptive)
    }

    func testClaudeOpus45_Optional() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-opus-4.5-20250514")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: false))
    }

    func testClaude_Default_Optional() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-sonnet-4-20250514")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: false))
    }

    // MARK: - Kimi 系列

    func testKimiK27Code_AlwaysOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "kimi-k2.7-code")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .alwaysOn)
    }

    func testKimiK26_OptionalThinking_DefaultOff() {
        let profile = ModelCapabilityRegistry.findProfile(for: "kimi-k2.6")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: false))
    }

    func testKimiK25_OptionalThinking_DefaultOff() {
        let profile = ModelCapabilityRegistry.findProfile(for: "kimi-k2.5")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: false))
    }

    // MARK: - Doubao 系列

    func testDoubaoSeed_OptionalThinking_DefaultOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "doubao-seed-1.6")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: true))
    }

    func testDoubao_NotSupported() {
        let profile = ModelCapabilityRegistry.findProfile(for: "doubao-pro")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .notSupported)
    }

    // MARK: - MiniMax 系列

    func testMiniMaxM3_OptionalThinking_DefaultOff() {
        let profile = ModelCapabilityRegistry.findProfile(for: "minimax-m3")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: false))
    }

    func testMiniMaxM2_AlwaysOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "minimax-m2.7")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .alwaysOn)
    }

    // MARK: - 未知模型

    func testUnknownModel_ReturnsNil() {
        let profile = ModelCapabilityRegistry.findProfile(for: "unknown-model-xyz")
        XCTAssertNil(profile)
    }

    // MARK: - 参数约束测试

    func testGPT55_TemperatureConstraint() {
        let profile = ModelCapabilityRegistry.findProfile(for: "gpt-5.5")!
        let tempConstraint = profile.constraints.first { $0.parameter == .temperature }
        XCTAssertNotNil(tempConstraint)
        XCTAssertEqual(tempConstraint?.condition, .always)
        XCTAssertTrue(tempConstraint?.reason.contains("不支持") ?? false)
    }

    func testDeepSeekV32_ThinkingConstraint() {
        let profile = ModelCapabilityRegistry.findProfile(for: "deepseek-v3.2")!
        let tempConstraint = profile.constraints.first { $0.parameter == .temperature }
        XCTAssertNotNil(tempConstraint)
        XCTAssertEqual(tempConstraint?.condition, .whenThinkingEnabled)
    }

    func testGLM_FrequencyPenaltyConstraint() {
        let profile = ModelCapabilityRegistry.findProfile(for: "glm-5")!
        let freqConstraint = profile.constraints.first { $0.parameter == .frequencyPenalty }
        XCTAssertNotNil(freqConstraint)
        XCTAssertEqual(freqConstraint?.condition, .always)
    }

    func testClaudeOpus48_TemperatureConstraint() {
        let profile = ModelCapabilityRegistry.findProfile(for: "claude-opus-4.8")!
        let tempConstraint = profile.constraints.first { $0.parameter == .temperature }
        XCTAssertNotNil(tempConstraint)
        XCTAssertEqual(tempConstraint?.condition, .always)
    }

    // MARK: - 默认档案测试

    func testDefaultProfile_NotSupported() {
        XCTAssertEqual(ModelCapabilityRegistry.defaultProfile.thinkingCapability, .notSupported)
    }

    func testDefaultProfile_HasBasicParameters() {
        let params = ModelCapabilityRegistry.defaultProfile.nativeParameters
        XCTAssertTrue(params.contains(.temperature))
        XCTAssertTrue(params.contains(.topP))
        XCTAssertTrue(params.contains(.maxTokens))
    }

    // MARK: - 大小写不敏感匹配测试

    func testCaseInsensitive_Uppercase_GPT55() {
        let profile = ModelCapabilityRegistry.findProfile(for: "GPT-5.5")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.id, "gpt-5.5")
    }

    func testCaseInsensitive_MixedCase_DeepSeek() {
        let profile = ModelCapabilityRegistry.findProfile(for: "DeEpSeEk-V4")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.id, "deepseek-v4")
    }

    func testCaseInsensitive_Uppercase_GLM() {
        let profile = ModelCapabilityRegistry.findProfile(for: "GLM-5")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.id, "glm-5")
    }

    func testCaseInsensitive_Uppercase_Kimi() {
        let profile = ModelCapabilityRegistry.findProfile(for: "KIMI-K2.6")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.id, "kimi-k2.6")
    }

    func testCaseInsensitive_Uppercase_Claude() {
        let profile = ModelCapabilityRegistry.findProfile(for: "CLAUDE-OPUS-4.8")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.id, "claude-4.8")
    }

    func testCaseInsensitive_Uppercase_Qwen() {
        let profile = ModelCapabilityRegistry.findProfile(for: "QWEN3-8B")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.id, "qwen3")
    }

    // MARK: - 新增模型测试

    // MiniMax M2.7/M2.5/M2.1（仅思考模式）
    func testMiniMaxM27_AlwaysOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "minimax-m2.7")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .alwaysOn)
    }

    func testMiniMaxM25_AlwaysOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "minimax-m2.5")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .alwaysOn)
    }

    func testMiniMaxM21_AlwaysOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "minimax-m2.1")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .alwaysOn)
    }

    // Qwen3.7 系列（混合模式，默认开启）
    func testQwen37Max_OptionalThinking_DefaultOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "qwen3.7-max")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: true))
    }

    func testQwen37Plus_OptionalThinking_DefaultOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "qwen3.7-plus")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: true))
    }

    // Qwen3.6 系列（混合模式，默认开启）
    func testQwen36Max_OptionalThinking_DefaultOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "qwen3.6-max-preview")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: true))
    }

    func testQwen36Flash_OptionalThinking_DefaultOn() {
        let profile = ModelCapabilityRegistry.findProfile(for: "qwen3.6-flash")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thinkingCapability, .optional(defaultOn: true))
    }
}
