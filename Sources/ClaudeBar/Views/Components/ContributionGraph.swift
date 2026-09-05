import SwiftUI

enum ContributionMetric: String, CaseIterable {
    case tokens = "Tokens"
    case cost   = "Cost"
}

/// A GitHub-style 53×7 contribution graph showing token or cost activity
/// over the past year, one cell per day.
struct ContributionGraph: View {
    let dayStats: [Date: DayStats]
    @Binding var metric: ContributionMetric

    // MARK: - Layout constants

    private let cellSize: CGFloat  = 6
    private let gap: CGFloat       = 1
    private let dayLabelWidth: CGFloat = 8
    private let numCols = 53
    private let numRows = 7

    private let gridCalendar = Calendar(identifier: .iso8601)

    // MARK: - Computed geometry

    private var colStep: CGFloat { cellSize + gap }
    private var rowStep: CGFloat { cellSize + gap }

    // MARK: - Grid data

    /// Monday of the current ISO week.
    private var currentWeekMonday: Date {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: components) ?? Date()
    }

    /// The Monday that starts column 0 (52 weeks before current week Monday).
    private var gridStart: Date {
        gridCalendar.date(byAdding: .weekOfYear, value: -52, to: currentWeekMonday) ?? currentWeekMonday
    }

    /// Returns the `Date` for a given (col, row) cell where row 0 = Monday.
    private func date(col: Int, row: Int) -> Date? {
        let offset = col * 7 + row
        return gridCalendar.date(byAdding: .day, value: offset, to: gridStart)
    }

    // MARK: - Color helpers

    /// Pure date-to-color mapping shared by rendering and regression tests.
    static func cellColor(for date: Date, dayStats: [Date: DayStats], metric: ContributionMetric) -> Color {
        let calendar = Calendar(identifier: .iso8601)
        guard let stats = dayStats[calendar.startOfDay(for: date)] else {
            return Color.primary.opacity(0.06)
        }
        switch metric {
        case .tokens:
            guard stats.tokens > 0 else { return Color.primary.opacity(0.06) }
            let maxTokens = max(1, dayStats.values.map(\.tokens).max() ?? 1)
            let ratio = Double(stats.tokens) / Double(maxTokens)
            // Rounded so equal inputs yield equal Colors (0.2 + 0.8 * 0.5 ≠ 0.6 in binary).
            return Color.blue.opacity(min(1.0, (0.2 + 0.8 * ratio).rounded(toPlaces: 4)))
        case .cost:
            guard stats.cost > 0 else { return Color.primary.opacity(0.06) }
            let maxCost = max(0.001, dayStats.values.map(\.cost).max() ?? 0.001)
            let ratio = stats.cost / maxCost
            if ratio < 0.33 {
                return Color.green.opacity(max(0.2, ratio))
            } else if ratio < 0.66 {
                return Color.orange.opacity(max(0.2, ratio))
            } else {
                return Color.red.opacity(max(0.2, ratio))
            }
        }
    }

    private func cellColor(for date: Date) -> Color {
        Self.cellColor(for: date, dayStats: dayStats, metric: metric)
    }

    // MARK: - Tooltip helper

    private func tooltipText(for date: Date) -> String {
        let dateStr = date.formatted(.dateTime.month(.abbreviated).day())
        guard let stats = dayStats[gridCalendar.startOfDay(for: date)] else {
            return "\(dateStr) — no data"
        }
        let tokStr  = stats.tokens.formatted(.number)
        let costStr = String(format: "$%.2f", stats.cost)
        return "\(dateStr) — \(tokStr) tokens / \(costStr)"
    }

    // MARK: - Month label data

    /// Returns unique month boundaries as (col, monthName) for positioning labels.
    private var monthLabels: [(col: Int, label: String)] {
        var seen = Set<String>()
        var labels: [(col: Int, label: String)] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        for col in 0..<numCols {
            // Use row 0 (Monday) for each column to determine the month
            guard let d = date(col: col, row: 0) else { continue }
            let monthKey = formatter.string(from: d)
            if !seen.contains(monthKey) {
                seen.insert(monthKey)
                labels.append((col: col, label: monthKey))
            }
        }
        return labels
    }

    // MARK: - Day-of-week labels

    private let dayLabels = ["M", "Tu", "W", "Th", "F", "Sa", "Su"]

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            metricPicker
            grid
        }
    }

    // MARK: - Picker

    private var metricPicker: some View {
        Picker("Metric", selection: $metric) {
            ForEach(ContributionMetric.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Grid

    private var grid: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Rows: one per weekday (Mon–Sun)
            ForEach(0..<numRows, id: \.self) { row in
                HStack(spacing: gap) {
                    // Day-of-week label
                    Text(dayLabels[row])
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(width: dayLabelWidth, alignment: .trailing)

                    // Week cells for this row
                    HStack(spacing: gap) {
                        ForEach(0..<numCols, id: \.self) { col in
                            if let d = date(col: col, row: row) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(cellColor(for: d))
                                    .frame(width: cellSize, height: cellSize)
                                    .help(tooltipText(for: d))
                            } else {
                                Color.clear
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }

            // Month labels row
            monthLabelRow
        }
    }

    // MARK: - Month label row

    private var monthLabelRow: some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(height: 12)
            ForEach(monthLabels, id: \.col) { item in
                Text(item.label)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .offset(x: dayLabelWidth + gap + CGFloat(item.col) * colStep)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContributionGraph(dayStats: [:], metric: .constant(.tokens))
        .padding()
        .frame(width: 420)
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
