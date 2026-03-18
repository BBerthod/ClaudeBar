import Foundation

/// Estimates API costs from token counts using published Anthropic pricing.
///
/// Prices are in USD per million tokens (MTok).
/// Cache-read tokens are much cheaper than fresh input tokens;
/// cache-write (creation) tokens carry a small premium over input tokens.
enum CostCalculator {

    // MARK: - ModelPricing

    struct ModelPricing: Sendable {
        /// USD per million input tokens.
        let inputPerMTok: Double
        /// USD per million output tokens.
        let outputPerMTok: Double
        /// USD per million cache-read tokens.
        let cacheReadPerMTok: Double
        /// USD per million cache-write (creation) tokens.
        let cacheWritePerMTok: Double
    }

    // MARK: - Pricing table

    /// Published Anthropic pricing as of early 2026.
    /// Keys are canonical model IDs; aliases are resolved in `pricing(for:)`.
    static let pricing: [String: ModelPricing] = [
        // Opus 4 / Opus 4.5
        "claude-opus-4-6": ModelPricing(
            inputPerMTok: 15.00,
            outputPerMTok: 75.00,
            cacheReadPerMTok: 1.50,
            cacheWritePerMTok: 18.75
        ),
        "claude-opus-4-5-20251101": ModelPricing(
            inputPerMTok: 15.00,
            outputPerMTok: 75.00,
            cacheReadPerMTok: 1.50,
            cacheWritePerMTok: 18.75
        ),

        // Sonnet 4 / Sonnet 4.5
        "claude-sonnet-4-6": ModelPricing(
            inputPerMTok: 3.00,
            outputPerMTok: 15.00,
            cacheReadPerMTok: 0.30,
            cacheWritePerMTok: 3.75
        ),
        "claude-sonnet-4-5-20250929": ModelPricing(
            inputPerMTok: 3.00,
            outputPerMTok: 15.00,
            cacheReadPerMTok: 0.30,
            cacheWritePerMTok: 3.75
        ),

        // Haiku 4.5
        "claude-haiku-4-5-20251001": ModelPricing(
            inputPerMTok: 0.25,
            outputPerMTok: 1.25,
            cacheReadPerMTok: 0.025,
            cacheWritePerMTok: 0.3125
        ),
    ]

    // MARK: - Public API

    /// Returns the pricing for a given model ID.
    ///
    /// Falls back to opus pricing for unknown model IDs — a conservative
    /// (over-) estimate rather than silently returning zero.
    static func pricing(for modelId: String) -> ModelPricing {
        if let p = pricing[modelId] { return p }

        // Partial-match aliases: any id containing "sonnet" → sonnet pricing,
        // any id containing "haiku" → haiku pricing, otherwise opus.
        let lower = modelId.lowercased()
        if lower.contains("haiku") {
            return pricing["claude-haiku-4-5-20251001"]!
        } else if lower.contains("sonnet") {
            return pricing["claude-sonnet-4-6"]!
        }
        return pricing["claude-opus-4-6"]!
    }

    /// Estimates the USD cost for a single model's usage entry.
    static func estimateCost(for usage: ModelUsageEntry, modelId: String) -> Double {
        let p = pricing(for: modelId)
        let mTok = 1_000_000.0

        let inputCost  = Double(usage.inputTokens)              / mTok * p.inputPerMTok
        let outputCost = Double(usage.outputTokens)             / mTok * p.outputPerMTok
        let readCost   = Double(usage.cacheReadInputTokens)     / mTok * p.cacheReadPerMTok
        let writeCost  = Double(usage.cacheCreationInputTokens) / mTok * p.cacheWritePerMTok

        return inputCost + outputCost + readCost + writeCost
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
            let p = pricing(for: modelId)
            let mTok = 1_000_000.0

            if let usage = modelUsage[modelId] {
                let cumulativeIO = usage.inputTokens + usage.outputTokens
                guard cumulativeIO > 0 else {
                    total += Double(tokenCount) / mTok * p.inputPerMTok
                    continue
                }
                // Daily fraction based on input+output only (matching tokensByModel scope).
                let fraction = Double(tokenCount) / Double(cumulativeIO)
                let inputCost  = Double(usage.inputTokens)              * fraction / mTok * p.inputPerMTok
                let outputCost = Double(usage.outputTokens)             * fraction / mTok * p.outputPerMTok
                let readCost   = Double(usage.cacheReadInputTokens)     * fraction / mTok * p.cacheReadPerMTok
                let writeCost  = Double(usage.cacheCreationInputTokens) * fraction / mTok * p.cacheWritePerMTok
                total += inputCost + outputCost + readCost + writeCost
            } else {
                total += Double(tokenCount) / mTok * p.inputPerMTok
            }
        }
        return total
    }

    /// Formats a cost value as a USD string, e.g. `"$12.34"` or `"$0.00"`.
    static func formatCost(_ cost: Double) -> String {
        String(format: "$%.2f", cost)
    }
}
