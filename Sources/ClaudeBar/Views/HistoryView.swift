import SwiftUI
import Charts

enum HistoryPeriod: String, CaseIterable {
    case week   = "7 days"
    case month  = "30 days"
    case all    = "All time"
}

enum HistoryChart: String, CaseIterable {
    case cost     = "Cost"
    case activity = "Activity"
}

struct HistoryView: View {
    var statsService: StatsService

    @State private var period: HistoryPeriod = .month
    @State private var chartType: HistoryChart = .cost

    private var filteredActivity: [DailyActivity] {
        let all = statsService.last30DaysActivity
        switch period {
        case .week:  return Array(all.suffix(7))
        case .month: return all
        case .all:   return all
        }
    }

    private var filteredTokens: [DailyModelTokens] {
        let all = statsService.last30DaysTokens
        switch period {
        case .week:  return Array(all.suffix(7))
        case .month: return all
        case .all:   return all
        }
    }

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Cost series

    /// Per-day estimated cost for the current period filter.
    private var costSeries: [(date: Date, cost: Double)] {
        guard let stats = statsService.stats else { return [] }
        return filteredTokens.compactMap { day in
            guard let date = Self.isoDateFormatter.date(from: day.date) else { return nil }
            let cost = CostCalculator.estimateDailyCost(
                tokens: day.tokensByModel,
                modelUsage: stats.modelUsage
            )
            return (date: date, cost: cost)
        }
    }

    /// Total cost summed over the current period.
    private var periodCost: Double {
        costSeries.reduce(0.0) { $0 + $1.cost }
    }

    // MARK: - Activity series

    /// Flat list of (date, model, tokens) for the token line chart.
    private var tokenSeries: [(date: Date, model: String, tokens: Int)] {
        filteredTokens.flatMap { day in
            let date = Self.isoDateFormatter.date(from: day.date) ?? Date()
            return day.tokensByModel.map { (model, tokens) in
                (date: date, model: StatsService.displayName(for: model), tokens: tokens)
            }
        }
    }

    private var allModels: [String] {
        Array(Set(tokenSeries.map(\.model))).sorted()
    }

    /// Activity data with parsed dates — messages and tool calls combined.
    private var activityWithDates: [(date: Date, messages: Int, toolCalls: Int)] {
        filteredActivity.compactMap { day in
            guard let date = Self.isoDateFormatter.date(from: day.date) else { return nil }
            return (date: date, messages: day.messageCount, toolCalls: day.toolCallCount)
        }
    }

    private var totalMessages: Int {
        filteredActivity.reduce(0) { $0 + $1.messageCount }
    }

    private var totalSessions: Int {
        filteredActivity.reduce(0) { $0 + $1.sessionCount }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                periodPicker
                chartTypePicker
                summaryCards
                chartsSection
                Spacer(minLength: 12)
            }
        }
    }

    // MARK: - Pickers

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(HistoryPeriod.allCases, id: \.self) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var chartTypePicker: some View {
        Picker("Chart", selection: $chartType) {
            ForEach(HistoryChart.allCases, id: \.self) { c in
                Text(c.rawValue).tag(c)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 8
        ) {
            StatCard(title: "Sessions", value: "\(totalSessions)", icon: "rectangle.stack")
            StatCard(title: "Messages", value: "\(totalMessages)", icon: "message")
            StatCard(
                title: "Est. Cost",
                value: CostCalculator.formatCost(periodCost),
                icon: "dollarsign.circle"
            )
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Charts section

    @ViewBuilder
    private var chartsSection: some View {
        if filteredTokens.isEmpty && filteredActivity.isEmpty {
            emptyState
        } else {
            switch chartType {
            case .cost:
                costChartSection
            case .activity:
                tokenChart
                messagesAndToolCallsChart
            }
        }
    }

    // MARK: - Cost chart

    @ViewBuilder
    private var costChartSection: some View {
        if !costSeries.isEmpty {
            sectionHeader("Daily Cost")
            Chart(costSeries, id: \.date) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Cost", point.cost)
                )
                .foregroundStyle(Color.accentColor.gradient)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 5)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.narrow))
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "$%.2f", v)).font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 150)
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Activity charts

    @ViewBuilder
    private var tokenChart: some View {
        if !tokenSeries.isEmpty {
            sectionHeader("Daily Tokens")
            Chart {
                ForEach(allModels, id: \.self) { model in
                    let modelData = tokenSeries.filter { $0.model == model }
                    ForEach(modelData.indices, id: \.self) { idx in
                        let point = modelData[idx]
                        LineMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Tokens", point.tokens)
                        )
                        .foregroundStyle(by: .value("Model", model))
                        .symbol(by: .value("Model", model))
                    }
                }
            }
            .chartForegroundStyleScale { modelId in Color.color(for: modelId) }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 5)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.narrow))
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(v.abbreviatedTokenCount).font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 120)
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private var messagesAndToolCallsChart: some View {
        if !activityWithDates.isEmpty {
            sectionHeader("Daily Messages & Tool Calls")
            Chart {
                ForEach(activityWithDates, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Count", point.messages)
                    )
                    .foregroundStyle(by: .value("Series", "Messages"))
                    .symbol(by: .value("Series", "Messages"))

                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Count", point.toolCalls)
                    )
                    .foregroundStyle(by: .value("Series", "Tool Calls"))
                    .symbol(by: .value("Series", "Tool Calls"))
                }
            }
            .chartForegroundStyleScale([
                "Messages":   Color.accentColor,
                "Tool Calls": Color.orange,
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 5)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.narrow))
                        .font(.caption2)
                }
            }
            .frame(height: 120)
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No history available")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Stats will appear after using Claude Code.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    HistoryView(statsService: StatsService())
        .frame(width: 420, height: 480)
}
