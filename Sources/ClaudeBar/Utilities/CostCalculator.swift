import Foundation

/// Estimates API costs from token counts using published Anthropic pricing.
///
/// Prices are in USD per million tokens (MTok).
/// Cache-read tokens are much cheaper than fresh input tokens;
/// cache-write (creation) tokens carry a small premium over input tokens.
enum CostCalculator {

    // MARK: - ModelPricing

    struct ModelPricing: Sendable {
        static let opus5Fallback = ModelPricing(inputPerMTok: 5, outputPerMTok: 25,
                                               cacheReadPerMTok: 0.5, cacheWritePerMTok: 6.25)

        /// USD per million input tokens.
        let inputPerMTok: Double
        /// USD per million output tokens.
        let outputPerMTok: Double
        /// USD per million cache-read tokens.
        let cacheReadPerMTok: Double
        /// USD per million cache-write (creation) tokens.
        let cacheWritePerMTok: Double
    }

    // MARK: - Public API

    static func pricing(for modelId: String) -> ModelPricing {
        let catalog = ModelCatalogService.current
        guard let entry = catalog.resolve(modelId)?.entry
            ?? catalog.entries["claude-opus-5"] else { return ModelPricing.opus5Fallback }
        return ModelPricing(inputPerMTok: entry.inputPerMTok, outputPerMTok: entry.outputPerMTok,
                            cacheReadPerMTok: entry.cacheReadPerMTok, cacheWritePerMTok: entry.cacheWritePerMTok)
    }

    static func isEstimated(_ modelId: String) -> Bool {
        ModelCatalogService.current.resolve(modelId)?.isEstimated ?? true
    }

    /// Estimates the USD-equivalent API cost for a day given the per-model
    /// token totals and the cumulative model-usage table.
    ///
    /// `tokensByModel` from stats-cache contains **input + output tokens only**
    /// (no cache reads/writes). We compute this day's share of all token types
    /// by using the I/O ratio against cumulative I/O, then scale cache costs
    /// proportionally.
    ///
    /// - Parameters:
    ///   - tokens: `tokensByModel` from a `DailyModelTokens` entry (I/O only).
    ///   - modelUsage: The full `modelUsage` table from `StatsCache`.
    static func estimateDailyCost(
        tokens: [String: Int],
        modelUsage: [String: ModelUsageEntry]
    ) -> Double {
        var total = 0.0
        for (modelId, tokenCount) in tokens {
            if let usage = modelUsage[modelId] {
                if let cost = proportionalCost(modelId: modelId, tokenCount: tokenCount, usage: usage) {
                    total += cost
                } else {
                    total += cost(modelId: modelId, input: tokenCount, output: 0, cacheRead: 0, cacheCreation: 0)
                }
            } else {
                total += cost(modelId: modelId, input: tokenCount, output: 0, cacheRead: 0, cacheCreation: 0)
            }
        }
        return total
    }

    /// Direct USD cost from the four token types (no scaling; we have all types).
    static func cost(modelId: String, input: Int, output: Int, cacheRead: Int, cacheCreation: Int) -> Double {
        let p = pricing(for: modelId)
        let mTok = 1_000_000.0
        return Double(input)         / mTok * p.inputPerMTok
             + Double(output)        / mTok * p.outputPerMTok
             + Double(cacheRead)     / mTok * p.cacheReadPerMTok
             + Double(cacheCreation) / mTok * p.cacheWritePerMTok
    }

    /// Estimates a model's cost from its share of cumulative input/output usage.
    static func proportionalCost(modelId: String, tokenCount: Int, usage: ModelUsageEntry) -> Double? {
        let cumulativeIO = usage.inputTokens + usage.outputTokens
        guard cumulativeIO > 0 else { return nil }
        let fraction = Double(tokenCount) / Double(cumulativeIO)
        return proportionalCost(pricing: pricing(for: modelId), usage: usage, fraction: fraction)
    }

    /// Returns the savings from cache-read tokens versus fresh input tokens.
    static func cacheSavings(modelId: String, cacheReadTokens: Int) -> Double {
        let p = pricing(for: modelId)
        return Double(cacheReadTokens) * (p.inputPerMTok - p.cacheReadPerMTok) / 1_000_000.0
    }

    /// Returns cache savings as a percentage of the uncached input price.
    static func cacheSavingsPercent(modelUsage: [String: ModelUsageEntry]) -> Double {
        let mTok = 1_000_000.0
        var fullPrice = 0.0
        var discountedPrice = 0.0
        for (modelId, usage) in modelUsage {
            let p = pricing(for: modelId)
            let cacheReadTokens = Double(usage.cacheReadInputTokens)
            fullPrice += cacheReadTokens * p.inputPerMTok / mTok
            discountedPrice += cacheReadTokens * p.cacheReadPerMTok / mTok
        }
        guard fullPrice > 0 else { return 0 }
        return (fullPrice - discountedPrice) / fullPrice * 100
    }

    /// Formats a cost value as a USD string, e.g. `"$12.34"` or `"$0.00"`.
    static func formatCost(_ cost: Double) -> String {
        String(format: "$%.2f", cost)
    }

    /// Computes per-model cost breakdown across all recorded days in `stats`.
    ///
    /// Returns an array sorted by cost descending; model names are the
    /// human-readable display names from `StatsService.displayName(for:)`.
    ///
    /// Marked `@MainActor` because `StatsService.displayName(for:)` is main-actor isolated.
    @MainActor
    static func modelCostBreakdown(stats: StatsCache) -> [(model: String, cost: Double)] {
        var costByModel: [String: Double] = [:]
        for day in stats.dailyModelTokens {
            for (modelId, tokenCount) in day.tokensByModel {
                let displayName = StatsService.displayName(for: modelId)
                if let usage = stats.modelUsage[modelId] {
                    guard let cost = proportionalCost(modelId: modelId, tokenCount: tokenCount, usage: usage) else {
                        // io is 0 but tokens exist — use input-only pricing as fallback
                        costByModel[displayName, default: 0] += cost(
                            modelId: modelId,
                            input: tokenCount,
                            output: 0,
                            cacheRead: 0,
                            cacheCreation: 0
                        )
                        continue
                    }
                    costByModel[displayName, default: 0] += cost
                } else {
                    // No detailed usage — use input-only pricing (matches estimateDailyCost fallback)
                    costByModel[displayName, default: 0] += cost(
                        modelId: modelId,
                        input: tokenCount,
                        output: 0,
                        cacheRead: 0,
                        cacheCreation: 0
                    )
                }
            }
        }
        return costByModel.map { (model: $0.key, cost: $0.value) }.sorted { $0.cost > $1.cost }
    }

    // MARK: - Private helpers

    private static func proportionalCost(
        pricing: ModelPricing,
        usage: ModelUsageEntry,
        fraction: Double
    ) -> Double {
        let mTok = 1_000_000.0
        let inputCost  = Double(usage.inputTokens)              * fraction / mTok * pricing.inputPerMTok
        let outputCost = Double(usage.outputTokens)             * fraction / mTok * pricing.outputPerMTok
        let readCost   = Double(usage.cacheReadInputTokens)     * fraction / mTok * pricing.cacheReadPerMTok
        let writeCost  = Double(usage.cacheCreationInputTokens) * fraction / mTok * pricing.cacheWritePerMTok
        return inputCost + outputCost + readCost + writeCost
    }
}
