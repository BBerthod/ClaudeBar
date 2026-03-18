import SwiftUI
import Charts

enum HistoryPeriod: String, CaseIterable {
    case week   = "7 days"
    case month  = "30 days"
    case all    = "All time"
}

struct HistoryView: View {
    var statsService: StatsService

    @State private var period: HistoryPeriod = .month

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

    /// Flat list of (date, model, tokens) for the line chart
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

    private var totalMessages: Int {
        filteredActivity.reduce(0) { $0 + $1.messageCount }
    }

    private var totalSessions: Int {
        filteredActivity.reduce(0) { $0 + $1.sessionCount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                periodPicker
                summaryCards
                chartsSection
                Spacer(minLength: 12)
            }
        }
    }

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

    private var summaryCards: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 8
        ) {
            StatCard(title: "Sessions", value: "\(totalSessions)", icon: "rectangle.stack")
            StatCard(title: "Messages", value: "\(totalMessages)", icon: "message")
            StatCard(
                title: "Est. Cost",
                value: CostCalculator.formatCost(statsService.totalCostEstimate),
                icon: "dollarsign.circle"
            )
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var chartsSection: some View {
        if filteredTokens.isEmpty && filteredActivity.isEmpty {
            emptyState
        } else {
            tokenChart
            messagesChart
        }
    }

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
            .chartForegroundStyleScale { modelId in
                Color.color(for: modelId)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 5)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
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

    /// Activity data with parsed Date for charts
    private var activityWithDates: [(date: Date, messages: Int)] {
        filteredActivity.compactMap { day in
            guard let date = Self.isoDateFormatter.date(from: day.date) else { return nil }
            return (date: date, messages: day.messageCount)
        }
    }

    @ViewBuilder
    private var messagesChart: some View {
        if !activityWithDates.isEmpty {
            sectionHeader("Daily Messages")
            Chart(activityWithDates, id: \.date) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Messages", point.messages)
                )
                .foregroundStyle(Color.accentColor.gradient)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 5)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                }
            }
            .frame(height: 100)
            .padding(.horizontal, 12)
        }
    }

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
