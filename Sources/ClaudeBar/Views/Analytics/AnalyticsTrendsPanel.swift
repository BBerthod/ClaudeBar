import SwiftUI
import Charts

struct AnalyticsTrendsPanel: View {
    let statsService: StatsService
    let sessionService: SessionService
    let burnRateService: BurnRateService
    let liveStatsService: LiveStatsService

    var body: some View {
        trendsPanel
    }
    // MARK: - Effective stats (prefer stats-cache, fallback to live JSONL)

    private var effectiveMessages: Int {
        statsService.todayMessages > 0 ? statsService.todayMessages : liveStatsService.todayMessages
    }

    private var effectiveSessions: Int {
        statsService.todaySessions > 0 ? statsService.todaySessions : sessionService.activeSessions.count
    }

    private var effectiveToolCalls: Int {
        statsService.todayToolCalls > 0 ? statsService.todayToolCalls : liveStatsService.todayToolCalls
    }

    private var effectiveTokens: Int {
        statsService.todayTokens > 0 ? statsService.todayTokens : liveStatsService.todayTokens
    }

    private var effectiveCost: Double {
        statsService.todayCostEstimate > 0 ? statsService.todayCostEstimate : liveStatsService.todayCost
    }

    // MARK: - Trends Panel

    private var dailyCosts: [(date: Date, cost: Double)] {
        guard let stats = statsService.stats else { return [] }
        return stats.last30DaysModelTokens.compactMap { day in
            guard let date = DateFormatter.isoDate.date(from: day.date) else { return nil }
            let cost = CostCalculator.estimateDailyCost(tokens: day.tokensByModel, modelUsage: stats.modelUsage)
            return (date: date, cost: cost)
        }
    }

    private var dailyMessages: [(date: Date, messages: Int)] {
        statsService.last30DaysActivity.compactMap { day in
            guard let date = DateFormatter.isoDate.date(from: day.date) else { return nil }
            return (date: date, messages: day.messageCount)
        }
    }

    private var trendsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Usage Trends")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)

                // Today summary card
                todaySummaryCard
                    .padding(.horizontal)

                // Cost trend
                GroupBox("Daily Cost (30 days)") {
                    Chart(dailyCosts, id: \.date) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Cost", point.cost)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(CostCalculator.formatCost(v))
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .frame(height: 200)
                    .padding(8)
                }
                .padding(.horizontal)

                // Messages trend
                GroupBox("Daily Messages (30 days)") {
                    Chart(dailyMessages, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Messages", point.messages)
                        )
                        .foregroundStyle(Color.green)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Messages", point.messages)
                        )
                        .foregroundStyle(Color.green.opacity(0.1))
                        .interpolationMethod(.catmullRom)
                    }
                    .frame(height: 180)
                    .padding(8)
                }
                .padding(.horizontal)

                // Cost per hour sparkline for today
                costPerHourCard
                    .padding(.horizontal)

                // Week comparison (visual bar chart)
                weekComparisonView
                    .padding(.horizontal)

                // Token breakdown by model
                modelBreakdownChart
                    .padding(.horizontal)

                // Hourly activity pattern
                hourlyPatternChart
                    .padding(.horizontal)

                // Key stats summary
                keyStatsGrid
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Today Summary Card

    private var todaySummaryCard: some View {
        GroupBox("Today so far") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 12
            ) {
                summaryTile(
                    "Cost",
                    value: CostCalculator.formatCost(effectiveCost),
                    icon: "dollarsign.circle",
                    color: .green
                )
                summaryTile(
                    "Messages",
                    value: "\(effectiveMessages)",
                    icon: "message",
                    color: .blue
                )
                summaryTile(
                    "Tokens",
                    value: effectiveTokens.abbreviatedTokenCount,
                    icon: "text.word.spacing",
                    color: .purple
                )
                summaryTile(
                    "Tool Calls",
                    value: "\(effectiveToolCalls)",
                    icon: "wrench.and.screwdriver",
                    color: .orange
                )
                summaryTile(
                    "Sessions",
                    value: "\(effectiveSessions)",
                    icon: "rectangle.stack",
                    color: .teal
                )
            }
            .padding(8)

            if liveStatsService.isStale {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("Live estimate — stats-cache has no entry for today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func summaryTile(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Cost Per Hour Card

    private var costPerHourCard: some View {
        GroupBox("Cost per Hour — Today") {
            if let rate = burnRateService.burnRate, rate.costPerHour > 0 {
                let now = Date()
                let calendar = Calendar.current
                let currentHour = calendar.component(.hour, from: now)

                // Build hourly data points: estimate based on cost distributed over active hours
                let hourlyPoints: [(hour: Int, cost: Double)] = (0..<max(currentHour + 1, 1)).map { h in
                    // Distribute today's cost evenly across active hours as a simplified sparkline
                    let hoursActive = max(rate.hoursActive, 1.0)
                    let costPerSlot = effectiveCost / hoursActive
                    return (hour: h, cost: h < Int(rate.hoursActive) ? costPerSlot : 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Chart(hourlyPoints, id: \.hour) { point in
                        BarMark(
                            x: .value("Hour", "\(point.hour)h"),
                            y: .value("Cost", point.cost)
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(CostCalculator.formatCost(v))
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .frame(height: 120)
                    .padding(8)

                    HStack {
                        Label(rate.costPerHourFormatted, systemImage: "flame")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Projected: \(rate.projectedCostFormatted)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)

                    Text("Estimated — cost distributed evenly over active hours")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                }
            } else {
                Text("No burn rate data available")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding()
            }
        }
    }

    // MARK: - Model Breakdown

    private var modelCosts: [(model: String, cost: Double)] {
        guard let stats = statsService.stats else { return [] }
        return CostCalculator.modelCostBreakdown(stats: stats)
    }

    private var modelBreakdownChart: some View {
        GroupBox("Cost by Model (All Time)") {
            if modelCosts.isEmpty {
                Text("No data").font(.caption).foregroundStyle(.tertiary).padding()
            } else {
                Chart(modelCosts, id: \.model) { entry in
                    SectorMark(
                        angle: .value("Cost", entry.cost),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(Color.color(for: entry.model))
                    .annotation(position: .overlay) {
                        if entry.cost / modelCosts.reduce(0, { $0 + $1.cost }) > 0.08 {
                            Text(CostCalculator.formatCost(entry.cost))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .chartLegend(position: .bottom)
                .frame(height: 220)
                .padding(8)
            }
        }
    }

    // MARK: - Hourly Pattern

    private var hourlyData: [(hour: Int, count: Int)] {
        guard let hourCounts = statsService.stats?.hourCounts else { return [] }
        return (0..<24).map { h in (hour: h, count: hourCounts[String(h)] ?? 0) }
    }

    private var hourlyPatternChart: some View {
        GroupBox("Activity by Hour (All Time)") {
            let data = hourlyData
            let maxCount = data.map(\.count).max() ?? 1
            if maxCount > 0 {
                Chart(data, id: \.hour) { point in
                    BarMark(
                        x: .value("Hour", "\(point.hour)"),
                        y: .value("Messages", point.count)
                    )
                    .foregroundStyle(
                        Double(point.count) / Double(maxCount) > 0.7
                            ? Color.orange.gradient
                            : Color.blue.opacity(0.6).gradient
                    )
                }
                .frame(height: 140)
                .padding(8)
            } else {
                Text("No hourly data").font(.caption).foregroundStyle(.tertiary).padding()
            }
        }
    }

    // MARK: - Key Stats Grid

    private var keyStatsGrid: some View {
        let stats = statsService.stats
        let totalSessions = stats?.totalSessions ?? 0
        let totalMessages = stats?.totalMessages ?? 0
        let totalDays = stats?.dailyModelTokens.count ?? 0
        let avgMessagesPerDay = totalDays > 0 ? totalMessages / totalDays : 0
        let avgCostPerDay = totalDays > 0 ? statsService.totalCostEstimate / Double(totalDays) : 0
        let speculationSaved = stats?.totalSpeculationTimeSavedMs ?? 0
        let specSeconds = speculationSaved / 1000
        let specFormatted = specSeconds >= 3600
            ? "\(specSeconds / 3600)h \((specSeconds % 3600) / 60)m"
            : "\(specSeconds / 60)m"

        return GroupBox("Lifetime Stats") {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                statTile("Total Sessions", value: "\(totalSessions)")
                statTile("Total Messages", value: totalMessages.abbreviatedTokenCount)
                statTile("Days Tracked", value: "\(totalDays)")
                statTile("Avg Msgs/Day", value: "\(avgMessagesPerDay)")
                statTile("Avg Cost/Day", value: CostCalculator.formatCost(avgCostPerDay))
                statTile("Time Saved", value: specFormatted)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func statTile(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Week Comparison (visual bar chart)

    private var weekComparisonView: some View {
        let costs = dailyCosts
        let thisWeek = costs.suffix(7).reduce(0.0) { $0 + $1.cost }
        let lastWeek = costs.dropLast(7).suffix(7).reduce(0.0) { $0 + $1.cost }
        let change = lastWeek > 0 ? ((thisWeek - lastWeek) / lastWeek) * 100 : 0
        let maxVal = max(thisWeek, lastWeek, 0.01)

        return GroupBox("Week over Week") {
            if thisWeek == 0 && lastWeek == 0 {
                Text("No spending data for the past two weeks")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding()
            } else {
            VStack(spacing: 16) {
                // Side-by-side bar chart
                HStack(alignment: .bottom, spacing: 24) {
                    // Last week bar
                    VStack(spacing: 6) {
                        Text(CostCalculator.formatCost(lastWeek))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 60, height: max(CGFloat(lastWeek / maxVal) * 120, 4))
                        Text("Last Week")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // This week bar
                    VStack(spacing: 6) {
                        Text(CostCalculator.formatCost(thisWeek))
                            .font(.caption)
                            .fontWeight(.bold)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(change > 20 ? Color.red.gradient : change < -20 ? Color.green.gradient : Color.accentColor.gradient)
                            .frame(width: 60, height: max(CGFloat(thisWeek / maxVal) * 120, 4))
                        Text("This Week")
                            .font(.caption2)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    // Change badge
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Change")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%+.0f%%", change))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(change > 20 ? .red : change < -20 ? .green : .primary)
                        if change < 0 {
                            Label("Spending less", systemImage: "arrow.down.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else if change > 20 {
                            Label("Spending more", systemImage: "arrow.up.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(height: 180)
            }
            } // end else
        }
    }

    // MARK: - Projects Panel

}

