import Foundation

/// Decision result for protocol switching in Codex Adaptor.
enum ProtocolSwitchDecision: Equatable {
    /// Switch silently without any confirmation dialog.
    case silentSwitch
    /// Show unsaved changes alert (Codex APP not running).
    case showUnsavedChangesAlert
    /// Show simple restart confirmation alert (Codex APP running, no unsaved changes).
    case showRestartConfirmAlert
    /// Show merged alert: unsaved changes + restart required (Codex APP running + unsaved changes).
    case showMergedAlert
}

/// Determines what action to take when switching communication protocols.
///
/// This component encapsulates the decision logic for protocol switching,
/// making it testable independent of SwiftUI state management.
enum ProtocolSwitchDecisionMaker {
    /// Decide what action to take when switching protocols.
    ///
    /// - Parameters:
    ///   - codexAppRunning: Whether Codex APP is currently running.
    ///   - hasUnsavedChanges: Whether there are unsaved custom model changes.
    /// - Returns: The appropriate decision for the UI to execute.
    static func decide(codexAppRunning: Bool, hasUnsavedChanges: Bool) -> ProtocolSwitchDecision {
        if codexAppRunning {
            return hasUnsavedChanges ? .showMergedAlert : .showRestartConfirmAlert
        } else {
            return hasUnsavedChanges ? .showUnsavedChangesAlert : .silentSwitch
        }
    }
}
