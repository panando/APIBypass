import XCTest
@testable import APIBypass

final class ModelParameterSupportTests: XCTestCase {

    // MARK: - InjectedParameter 枚举测试

    func testInjectedParameter_AllCases() {
        let allCases = InjectedParameter.allCases
        XCTAssertTrue(allCases.contains(.temperature))
        XCTAssertTrue(allCases.contains(.topP))
        XCTAssertTrue(allCases.contains(.topK))
        XCTAssertTrue(allCases.contains(.frequencyPenalty))
        XCTAssertTrue(allCases.contains(.presencePenalty))
        XCTAssertTrue(allCases.contains(.maxTokens))
        XCTAssertTrue(allCases.contains(.maxOutputTokens))
        XCTAssertTrue(allCases.contains(.thinkingType))
        XCTAssertTrue(allCases.contains(.budgetTokens))
        XCTAssertTrue(allCases.contains(.reasoningEffort))
        XCTAssertTrue(allCases.contains(.thinkingBudget))
    }

    func testInjectedParameter_RawValue() {
        XCTAssertEqual(InjectedParameter.temperature.rawValue, "temperature")
        XCTAssertEqual(InjectedParameter.topP.rawValue, "topP")
        XCTAssertEqual(InjectedParameter.thinkingType.rawValue, "thinkingType")
    }

    // MARK: - ThinkingCapability 测试

    func testThinkingCapability_Equality() {
        XCTAssertEqual(ThinkingCapability.alwaysOn, ThinkingCapability.alwaysOn)
        XCTAssertEqual(ThinkingCapability.optional(defaultOn: true), ThinkingCapability.optional(defaultOn: true))
        XCTAssertNotEqual(ThinkingCapability.optional(defaultOn: true), ThinkingCapability.optional(defaultOn: false))
        XCTAssertEqual(ThinkingCapability.adaptive, ThinkingCapability.adaptive)
        XCTAssertEqual(ThinkingCapability.notSupported, ThinkingCapability.notSupported)
    }

    // MARK: - ParameterVisibility 测试

    func testParameterVisibility_Equality() {
        XCTAssertEqual(ParameterVisibility.supported, ParameterVisibility.supported)
        XCTAssertEqual(ParameterVisibility.hidden, ParameterVisibility.hidden)
        XCTAssertEqual(ParameterVisibility.disabledWithReason("test"), ParameterVisibility.disabledWithReason("test"))
        XCTAssertNotEqual(ParameterVisibility.disabledWithReason("test"), ParameterVisibility.disabledWithReason("other"))
    }

    // MARK: - ThinkingVisibility 测试

    func testThinkingVisibility_Equality() {
        XCTAssertEqual(ThinkingVisibility.hidden, ThinkingVisibility.hidden)
        XCTAssertEqual(ThinkingVisibility.visibleAndForced, ThinkingVisibility.visibleAndForced)
        XCTAssertEqual(ThinkingVisibility.visibleAndToggleable(defaultOn: true), ThinkingVisibility.visibleAndToggleable(defaultOn: true))
        XCTAssertNotEqual(ThinkingVisibility.visibleAndToggleable(defaultOn: true), ThinkingVisibility.visibleAndToggleable(defaultOn: false))
    }

    // MARK: - ParameterConstraint 测试

    func testParameterConstraint_Equality() {
        let constraint1 = ParameterConstraint(
            parameter: .temperature,
            condition: .whenThinkingEnabled,
            reason: "test"
        )
        let constraint2 = ParameterConstraint(
            parameter: .temperature,
            condition: .whenThinkingEnabled,
            reason: "test"
        )
        XCTAssertEqual(constraint1, constraint2)
    }

    func testConstraintCondition_Equality() {
        XCTAssertEqual(ConstraintCondition.whenThinkingEnabled, ConstraintCondition.whenThinkingEnabled)
        XCTAssertEqual(ConstraintCondition.always, ConstraintCondition.always)
        XCTAssertEqual(ConstraintCondition.fixedValue(1.0), ConstraintCondition.fixedValue(1.0))
        XCTAssertNotEqual(ConstraintCondition.fixedValue(1.0), ConstraintCondition.fixedValue(2.0))
    }
}
