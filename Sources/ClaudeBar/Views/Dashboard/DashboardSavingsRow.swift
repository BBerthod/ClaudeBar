import SwiftUI

struct DashboardSavingsRow: View {
    let statsService: StatsService

    var body: some View {
        if cacheSavings > 0.001 {
            cacheSavingsRow
                .padding(.horizontal, 12)
        }
    }
    // MARK: - Cache Savings

    /// How much prompt caching saved vs paying full input price for those tokens.
    var cacheSavings: Double {
        guard let modelUsage = statsService.stats?.modelUsage else { return 0 }
        var savings = 0.0
        for (modelId, usage) in modelUsage {
            savings += CostCalculator.cacheSavings(
                modelId: modelId,
                cacheReadTokens: usage.cacheReadInputTokens
            )
        }
        return savings
    }

    /// Cache savings as a percentage of what the total cost would have been without caching.
    private var cacheSavingsPercent: Double {
        guard let modelUsage = statsService.stats?.modelUsage else { return 0 }
        return CostCalculator.cacheSavingsPercent(modelUsage: modelUsage)
    }

    // MARK: - Cache Savings Row

    private var cacheSavingsRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 12))
                .foregroundStyle(.green)

            Text("Cache saved \(CostCalculator.formatCost(cacheSavings))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if cacheSavingsPercent > 0 {
                Text("\(Int(cacheSavingsPercent))% cheaper")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
                    .help("Percentage saved on cache-eligible tokens vs full input price")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.green.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
