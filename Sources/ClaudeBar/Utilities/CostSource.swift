import Foundation

/// Picks between the legacy stats-cache figures and the JSONL-history figures.
enum CostSource {
    /// stats-cache figure when present (> 0), otherwise the JSONL history figure.
    static func totalCost(statsCache: Double, history: Double) -> Double {
        statsCache > 0 ? statsCache : history
    }

    /// stats-cache day count when present (> 0), otherwise the JSONL history day count.
    static func trackedDays(statsCache: Int, history: Int) -> Int {
        statsCache > 0 ? statsCache : history
    }
}
