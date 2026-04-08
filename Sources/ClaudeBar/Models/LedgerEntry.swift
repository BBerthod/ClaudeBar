import Foundation

/// One assistant message parsed from a JSONL session file.
struct LedgerEntry: Identifiable, Sendable {
    let id: String            // message ID (deduplication key)
    let timestamp: Date
    let model: String         // raw model ID
    let projectName: String   // last path component of project directory
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let estimatedCost: Double
    let toolCallCount: Int

    @MainActor var displayModel: String { StatsService.displayName(for: model) }
    var totalTokens: Int { inputTokens + outputTokens }
}
