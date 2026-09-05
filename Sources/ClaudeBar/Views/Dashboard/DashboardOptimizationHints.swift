import SwiftUI

struct OptimizationHint: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let color: Color
}

struct DashboardOptimizationHints: View {
    let statsService: StatsService
    let burnRateService: BurnRateService
    let effectiveTokensByModel: [(model: String, tokens: Int)]
    let effectiveCost: Double
    let cacheSavings: Double

    var body: some View {
        if !optimizationHints.isEmpty {
            optimizationHintsSection
                .padding(.horizontal, 12)
        }
    }
    // MARK: - Optimization Hints

    private var optimizationHints: [OptimizationHint] {
        var hints: [OptimizationHint] = []

        // Rule 1: Opus tokens > 50% of total → suggest Sonnet for simpler tasks
        let tokensByModel = effectiveTokensByModel
        let totalTokens = tokensByModel.reduce(0) { $0 + $1.tokens }
        if totalTokens > 0 {
            let opusTokens = tokensByModel
                .filter { $0.model.lowercased().contains("opus") }
                .reduce(0) { $0 + $1.tokens }
            if Double(opusTokens) / Double(totalTokens) > 0.5 {
                hints.append(OptimizationHint(
                    icon: "arrow.down.circle",
                    text: "Opus is \(Int(Double(opusTokens) / Double(totalTokens) * 100))% of tokens — use Sonnet for simpler tasks",
                    color: .purple
                ))
            }
        }

        // Rule 2: Low cache savings with significant cost → suggest caching
        if cacheSavings < 0.01 && effectiveCost > 0.10 && statsService.cacheHitRate == nil {
            hints.append(OptimizationHint(
                icon: "bolt.horizontal.circle",
                text: "Low cache savings — enable prompt caching to reduce costs",
                color: .orange
            ))
        }

        // Rule 3: Cache efficiency feedback based on hit rate
        if let rate = statsService.cacheHitRate {
            let pct = String(format: "%.0f%%", rate * 100)
            if rate >= 0.7 {
                hints.append(OptimizationHint(
                    icon: "bolt.fill",
                    text: "Cache efficiency: \(pct) (alltime) — prompt caching is saving you tokens",
                    color: .green
                ))
            } else if rate < 0.4 {
                hints.append(OptimizationHint(
                    icon: "bolt",
                    text: "Cache efficiency: \(pct) (alltime) — consider structuring prompts to benefit from caching",
                    color: .orange
                ))
            }
        }

        // Rule 4: Hot/critical burn rate → show projected vs average
        if let rate = burnRateService.burnRate,
           rate.zone == .hot || rate.zone == .critical {
            hints.append(OptimizationHint(
                icon: rate.zone.icon,
                text: "Projected \(rate.projectedCostFormatted) today vs \(CostCalculator.formatCost(rate.averageDailyCost)) average",
                color: rate.zone == .critical ? .red : .orange
            ))
        }

        return hints
    }

    // MARK: - Optimization Hints Section

    private var optimizationHintsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Optimization Hints")
                .font(.subheadline)
                .fontWeight(.medium)

            ForEach(optimizationHints) { hint in
                HStack(spacing: 8) {
                    Image(systemName: hint.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(hint.color)

                    Text(hint.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hint.color.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

