import SwiftUI

struct ModelsBreakdownView: View {
    let breakdown: [String: ModelTokenBreakdown]

    private var summaries: [ModelCostSummary] {
        ModelBreakdown.summaries(from: breakdown)
    }

    private var total: Double {
        summaries.reduce(0) { $0 + $1.cost }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Models")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)

                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(CostCalculator.formatCost(total))
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                Text("Last 30 days")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        if summaries.isEmpty {
                            Divider()
                            Text("No model data available")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        } else {
                            Divider()

                            VStack(spacing: 0) {
                                ForEach(summaries) { summary in
                                    modelRow(summary)

                                    if summary.id != summaries.last?.id {
                                        Divider().padding(.horizontal, 8)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
            }
        }
    }

    private func modelRow(_ summary: ModelCostSummary) -> some View {
        let share = total > 0 ? summary.cost / total : 0
        let cacheReadRatio = summary.breakdown.total > 0
            ? Double(summary.breakdown.cacheRead) / Double(summary.breakdown.total)
            : 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(CostCalculator.formatCost(summary.cost))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            ProgressView(value: min(max(share, 0), 1))
                .tint(.accentColor)

            Text(tokenSplitText(for: summary.breakdown, cacheReadRatio: cacheReadRatio))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private func tokenSplitText(for breakdown: ModelTokenBreakdown, cacheReadRatio: Double) -> String {
        "in \(Self.compactTokens(breakdown.input)) / out \(Self.compactTokens(breakdown.output)) / cache-create \(Self.compactTokens(breakdown.cacheCreation)) / cache-read \(Self.compactTokens(breakdown.cacheRead)) (\(Self.percent(cacheReadRatio)))"
    }

    private static func compactTokens(_ value: Int) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000.0)
        }
        return "\(value)"
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f%% cache-read", value * 100)
    }
}
