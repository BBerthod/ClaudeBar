import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ExportService {

    enum Format {
        case csv
        case json
    }

    /// Exports stats data to a file chosen by the user via NSSavePanel.
    static func export(statsService: StatsService, format: Format) {
        guard let stats = statsService.stats else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        switch format {
        case .csv:
            panel.nameFieldStringValue = "claude-stats.csv"
            panel.allowedContentTypes = [UTType.commaSeparatedText]
        case .json:
            panel.nameFieldStringValue = "claude-stats.json"
            panel.allowedContentTypes = [UTType.json]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let content: String
        switch format {
        case .csv:  content = buildCSV(stats: stats, modelUsage: stats.modelUsage)
        case .json: content = buildJSON(stats: stats, modelUsage: stats.modelUsage)
        }

        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - CSV

    private static func buildCSV(stats: StatsCache, modelUsage: [String: ModelUsageEntry]) -> String {
        var lines: [String] = []
        lines.append("date,sessions,messages,tool_calls,tokens,cost_usd")

        let activityByDate = Dictionary(uniqueKeysWithValues: stats.dailyActivity.map { ($0.date, $0) })
        let tokensByDate = Dictionary(uniqueKeysWithValues: stats.dailyModelTokens.map { ($0.date, $0) })

        // Collect all dates from both sources
        let allDates = Set(activityByDate.keys).union(tokensByDate.keys).sorted()

        for date in allDates {
            let activity = activityByDate[date]
            let tokens = tokensByDate[date]

            let totalTokens = tokens?.tokensByModel.values.reduce(0, +) ?? 0
            let cost = tokens.map {
                CostCalculator.estimateDailyCost(tokens: $0.tokensByModel, modelUsage: modelUsage)
            } ?? 0

            lines.append("\(date),\(activity?.sessionCount ?? 0),\(activity?.messageCount ?? 0),\(activity?.toolCallCount ?? 0),\(totalTokens),\(String(format: "%.4f", cost))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON

    private static func buildJSON(stats: StatsCache, modelUsage: [String: ModelUsageEntry]) -> String {
        let activityByDate = Dictionary(uniqueKeysWithValues: stats.dailyActivity.map { ($0.date, $0) })
        let tokensByDate = Dictionary(uniqueKeysWithValues: stats.dailyModelTokens.map { ($0.date, $0) })

        let allDates = Set(activityByDate.keys).union(tokensByDate.keys).sorted()

        var dailyData: [[String: Any]] = []
        var totalCost = 0.0

        for date in allDates {
            let activity = activityByDate[date]
            let tokens = tokensByDate[date]

            let totalTokens = tokens?.tokensByModel.values.reduce(0, +) ?? 0
            let cost = tokens.map {
                CostCalculator.estimateDailyCost(tokens: $0.tokensByModel, modelUsage: modelUsage)
            } ?? 0
            totalCost += cost

            let entry: [String: Any] = [
                "date": date,
                "sessions": activity?.sessionCount ?? 0,
                "messages": activity?.messageCount ?? 0,
                "tool_calls": activity?.toolCallCount ?? 0,
                "tokens": totalTokens,
                "cost_usd": (cost * 10000).rounded() / 10000
            ]
            dailyData.append(entry)
        }

        let root: [String: Any] = [
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "total_cost_usd": (totalCost * 100).rounded() / 100,
            "total_sessions": stats.totalSessions,
            "total_messages": stats.totalMessages,
            "daily_data": dailyData
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}
