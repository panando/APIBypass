import Foundation

struct RectifierResult {
    var applied = false
    var removedThinkingBlocks = 0
    var removedRedactedThinkingBlocks = 0
    var removedSignatureFields = 0
    var removedTopLevelThinking = false
}

struct BudgetRectifierResult {
    let applied: Bool
    let before: BudgetSnapshot
    let after: BudgetSnapshot
}

struct BudgetSnapshot: Equatable {
    let maxTokens: Int?
    let thinkingType: String?
    let thinkingBudgetTokens: Int?
}
