import XCTest
@testable import APIBypass

/// Tests for protocol switch decision logic.
///
/// These tests verify the correct behavior when switching communication protocols
/// in the Codex Adaptor, based on whether Codex APP is running and whether there
/// are unsaved custom model changes.
final class ProtocolSwitchDecisionTests: XCTestCase {

    // MARK: - Decision Tests

    /// When Codex APP is not running and there are no unsaved changes,
    /// the switch should happen silently without any confirmation.
    func test_codexNotRunning_noUnsavedChanges_silentSwitch() {
        let decision = ProtocolSwitchDecisionMaker.decide(
            codexAppRunning: false,
            hasUnsavedChanges: false
        )
        XCTAssertEqual(decision, .silentSwitch)
    }

    /// When Codex APP is not running but there are unsaved changes,
    /// show the unsaved changes alert (original behavior).
    func test_codexNotRunning_hasUnsavedChanges_showUnsavedChangesAlert() {
        let decision = ProtocolSwitchDecisionMaker.decide(
            codexAppRunning: false,
            hasUnsavedChanges: true
        )
        XCTAssertEqual(decision, .showUnsavedChangesAlert)
    }

    /// When Codex APP is running but there are no unsaved changes,
    /// show the simple restart confirmation alert.
    func test_codexRunning_noUnsavedChanges_showRestartConfirmAlert() {
        let decision = ProtocolSwitchDecisionMaker.decide(
            codexAppRunning: true,
            hasUnsavedChanges: false
        )
        XCTAssertEqual(decision, .showRestartConfirmAlert)
    }

    /// When Codex APP is running AND there are unsaved changes,
    /// show the merged alert (unsaved changes + restart required).
    func test_codexRunning_hasUnsavedChanges_showMergedAlert() {
        let decision = ProtocolSwitchDecisionMaker.decide(
            codexAppRunning: true,
            hasUnsavedChanges: true
        )
        XCTAssertEqual(decision, .showMergedAlert)
    }
}
