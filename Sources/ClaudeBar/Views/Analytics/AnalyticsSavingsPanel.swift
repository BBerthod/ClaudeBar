import SwiftUI

struct AnalyticsSavingsPanel: View {
    let statsService: StatsService
    let yearlyHistoryService: YearlyHistoryService

    var body: some View {
        savingsPanel
    }
    private var savingsPanel: some View {
        let totalApiCost = statsService.totalCostEstimate
        let monthlySubscription = 200.0
        let days = Double(statsService.stats?.dailyModelTokens.count ?? 1)
        let months = max(days / 30.0, 1.0)
        let totalSubscriptionCost = months * monthlySubscription
        let saved = totalApiCost - totalSubscriptionCost
        let multiplier = totalSubscriptionCost > 0 ? totalApiCost / totalSubscriptionCost : 0
        let avgDailyApiCost = totalApiCost / max(days, 1)
        let projectedAnnualSavings = max((avgDailyApiCost - (monthlySubscription / 30)) * 365, 0)

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Max Plan Savings")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)

                Text("Based on Claude Max plan at $200/mo")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)

                // Main savings card
                GroupBox {
                    VStack(spacing: 20) {
                        HStack(spacing: 40) {
                            VStack(spacing: 4) {
                                Text("API Equivalent")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(CostCalculator.formatCost(totalApiCost))
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.red)
                            }

                            Image(systemName: "arrow.right")
                                .font(.title2)
                                .foregroundStyle(.secondary)

                            VStack(spacing: 4) {
                                Text("Max Plan Cost")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(CostCalculator.formatCost(totalSubscriptionCost))
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Divider()

                        VStack(spacing: 8) {
                            Text("You saved")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text(CostCalculator.formatCost(max(saved, 0)))
                                .font(.system(size: 48, weight: .bold))
                                .foregroundStyle(.green)
                                .help("Difference between API pricing and your Max subscription cost")

                            Text("×\(Int(multiplier)) return on your Max subscription")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        HStack(spacing: 40) {
                            VStack(spacing: 2) {
                                Text("\(Int(days))")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("days tracked")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(spacing: 2) {
                                Text(CostCalculator.formatCost(avgDailyApiCost))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("avg/day (API)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(spacing: 2) {
                                Text(CostCalculator.formatCost(monthlySubscription / 30))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("avg/day (Max)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
                .padding(.horizontal)

                // Monthly breakdown table
                if let stats = statsService.stats, !stats.dailyModelTokens.isEmpty {
                    monthlyBreakdownTable(stats: stats, monthlySubscription: monthlySubscription)
                        .padding(.horizontal)
                }

                // Projection card
                if projectedAnnualSavings > 0 {
                    GroupBox("Projection") {
                        HStack(spacing: 16) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.title2)
                                .foregroundStyle(.green)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("At this rate, you'll save approximately")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(CostCalculator.formatCost(projectedAnnualSavings))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                                Text("over the next 12 months")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func buildMonthlyMap(stats: StatsCache) -> [String: Double] {
        var monthlyMap: [String: Double] = [:]
        for day in stats.dailyModelTokens {
            guard DateFormatter.isoDate.date(from: day.date) != nil else { continue }
            let monthKey = String(day.date.prefix(7)) // "yyyy-MM"
            let cost = CostCalculator.estimateDailyCost(tokens: day.tokensByModel, modelUsage: stats.modelUsage)
            monthlyMap[monthKey, default: 0] += cost
        }
        return monthlyMap
    }

    private static let monthKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static let monthDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    @ViewBuilder
    private func monthlyBreakdownTable(stats: StatsCache, monthlySubscription: Double) -> some View {
        let monthlyMap = buildMonthlyMap(stats: stats)
        let sortedMonths = monthlyMap.keys.sorted()

        GroupBox("Monthly Breakdown") {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Month")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("API Cost")
                        .frame(width: 80, alignment: .trailing)
                    Text("Max Cost")
                        .frame(width: 80, alignment: .trailing)
                    Text("Savings")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                Divider()

                ForEach(sortedMonths, id: \.self) { monthKey in
                    let apiCost = monthlyMap[monthKey] ?? 0
                    let savings = apiCost - monthlySubscription
                    let isLast = monthKey == sortedMonths.last

                    HStack {
                        Text(Self.monthKeyFormatter.date(from: monthKey).map { Self.monthDisplayFormatter.string(from: $0) } ?? monthKey)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(CostCalculator.formatCost(apiCost))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.red)
                            .frame(width: 80, alignment: .trailing)

                        Text(CostCalculator.formatCost(monthlySubscription))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)

                        Text(CostCalculator.formatCost(max(savings, 0)))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .foregroundStyle(savings > 0 ? .green : .secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)

                    if !isLast {
                        Divider().padding(.horizontal, 8)
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - System Panel

}

