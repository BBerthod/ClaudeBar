import Foundation

struct ModelCostSummary: Sendable, Identifiable {
    let model: String
    let displayName: String
    let breakdown: ModelTokenBreakdown
    let cost: Double
    var id: String { model }
}

enum ModelBreakdown {
    /// Cleans a raw model id into a display name: drop "claude-" prefix, capitalize segments.
    static func displayName(for modelId: String) -> String {
        let stripped = modelId.hasPrefix("claude-") ? String(modelId.dropFirst("claude-".count)) : modelId
        return stripped
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Builds per-model cost summaries, sorted by cost descending.
    static func summaries(from breakdown: [String: ModelTokenBreakdown]) -> [ModelCostSummary] {
        breakdown.map { model, b in
            ModelCostSummary(
                model: model,
                displayName: displayName(for: model),
                breakdown: b,
                cost: CostCalculator.cost(
                    modelId: model,
                    input: b.input,
                    output: b.output,
                    cacheRead: b.cacheRead,
                    cacheCreation: b.cacheCreation
                )
            )
        }.sorted { $0.cost > $1.cost }
    }
}
