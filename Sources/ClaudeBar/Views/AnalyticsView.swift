import SwiftUI
import Charts

enum AnalyticsSection: String, CaseIterable {
    case alerts   = "Alerts"
    case trends   = "Trends"
    case projects = "Projects"
    case savings  = "Savings"

    var icon: String {
        switch self {
        case .alerts:   "bell.badge"
        case .trends:   "chart.line.uptrend.xyaxis"
        case .projects: "folder"
        case .savings:  "banknote"
        }
    }
}

struct AnalyticsView: View {
    var statsService: StatsService
    var sessionService: SessionService
    var burnRateService: BurnRateService
    var usageService: UsageService
    var liveStatsService: LiveStatsService
    var mcpHealthService: McpHealthService

    @State private var selectedSection: AnalyticsSection = .alerts

    var body: some View {
        NavigationSplitView {
            List(AnalyticsSection.allCases, id: \.self, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 200)
        } detail: {
            switch selectedSection {
            case .alerts:   alertsPanel
            case .trends:   trendsPanel
            case .projects: projectsPanel
            case .savings:  savingsPanel
            }
        }
    }

    // MARK: - Alerts Panel

    private var alertsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Smart Alerts")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)

                ForEach(activeAlerts, id: \.message) { alert in
                    alertRow(alert)
                        .padding(.horizontal)
                }

                if activeAlerts.isEmpty {
                    ContentUnavailableView(
                        "All Clear",
                        systemImage: "checkmark.shield",
                        description: Text("No alerts right now.")
                    )
                    .padding(.top, 60)
                }
            }
        }
    }

    private struct AlertItem {
        let severity: AlertSeverity
        let icon: String
        let title: String
        let message: String

        enum AlertSeverity { case info, warning, critical }
    }

    private var activeAlerts: [AlertItem] {
        var alerts: [AlertItem] = []

        // Context window alerts
        for session in sessionService.activeSessions {
            if let ctx = sessionService.contextEstimates[session.sessionId], ctx > 0.8 {
                alerts.append(AlertItem(
                    severity: ctx > 0.95 ? .critical : .warning,
                    icon: "gauge.with.dots.needle.100percent",
                    title: "Context \(Int(ctx * 100))%",
                    message: "\(session.projectName) is running out of context window"
                ))
            }
        }

        // 5h rate limit projection
        if let fiveHour = usageService.usage?.fiveHour {
            let elapsed = usageService.fiveHourElapsedFraction
            if elapsed > 0.1 {
                let projected = fiveHour.utilization / elapsed
                if projected > 100 {
                    alerts.append(AlertItem(
                        severity: .critical,
                        icon: "exclamationmark.triangle.fill",
                        title: "Rate Limit Risk",
                        message: "5h window projected to hit \(Int(min(projected, 999)))% at current pace"
                    ))
                } else if projected > 80 {
                    alerts.append(AlertItem(
                        severity: .warning,
                        icon: "exclamationmark.triangle",
                        title: "Rate Limit Warning",
                        message: "5h window projected to \(Int(projected))%"
                    ))
                }
            }
        }

        // Burn rate alerts
        if let rate = burnRateService.burnRate, rate.percentOfAverage > 2.0 {
            alerts.append(AlertItem(
                severity: .warning,
                icon: "flame.fill",
                title: "High Burn Rate",
                message: "Today's usage is \(Int(rate.percentOfAverage * 100))% of your daily average"
            ))
        }

        // Stats-cache staleness
        if let lastDate = statsService.stats?.lastComputedDate {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            if let date = f.date(from: lastDate) {
                let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
                if days > 1 {
                    alerts.append(AlertItem(
                        severity: .info,
                        icon: "clock.arrow.circlepath",
                        title: "Stats Cache Stale",
                        message: "Last updated \(days) days ago — Claude Code will refresh it automatically"
                    ))
                }
            }
        }

        // MCP server issues
        for server in mcpHealthService.servers {
            if case .unhealthy(let err) = server.status {
                alerts.append(AlertItem(
                    severity: .warning,
                    icon: "server.rack",
                    title: "MCP Down: \(server.name)",
                    message: err
                ))
            }
        }

        return alerts
    }

    @ViewBuilder
    private func alertRow(_ alert: AlertItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: alert.icon)
                .font(.title3)
                .foregroundStyle(alertColor(alert.severity))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.headline)
                Text(alert.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(alertColor(alert.severity).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func alertColor(_ severity: AlertItem.AlertSeverity) -> Color {
        switch severity {
        case .info:     return .blue
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    // MARK: - Trends Panel

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var dailyCosts: [(date: Date, cost: Double)] {
        guard let stats = statsService.stats else { return [] }
        return stats.last30DaysModelTokens.compactMap { day in
            guard let date = Self.isoDateFormatter.date(from: day.date) else { return nil }
            let cost = CostCalculator.estimateDailyCost(tokens: day.tokensByModel, modelUsage: stats.modelUsage)
            return (date: date, cost: cost)
        }
    }

    private var dailyMessages: [(date: Date, messages: Int)] {
        statsService.last30DaysActivity.compactMap { day in
            guard let date = Self.isoDateFormatter.date(from: day.date) else { return nil }
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

                // Week comparison
                weekComparisonView
                    .padding(.horizontal)
            }
        }
    }

    private var weekComparisonView: some View {
        let costs = dailyCosts
        let thisWeek = costs.suffix(7).reduce(0.0) { $0 + $1.cost }
        let lastWeek = costs.dropLast(7).suffix(7).reduce(0.0) { $0 + $1.cost }
        let change = lastWeek > 0 ? ((thisWeek - lastWeek) / lastWeek) * 100 : 0

        return GroupBox("Week over Week") {
            HStack(spacing: 40) {
                VStack(spacing: 4) {
                    Text("This Week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CostCalculator.formatCost(thisWeek))
                        .font(.title)
                        .fontWeight(.bold)
                }
                VStack(spacing: 4) {
                    Text("Last Week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CostCalculator.formatCost(lastWeek))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    Text("Change")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%+.0f%%", change))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(change > 20 ? .red : change < -20 ? .green : .primary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    // MARK: - Projects Panel

    private var projectsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Project Analytics")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)

                Text("Detailed per-project analytics coming in the next round. For now, see the Projects tab in the popover.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Savings Panel

    private var savingsPanel: some View {
        let totalApiCost = statsService.totalCostEstimate
        let monthlySubscription = 200.0
        let days = Double(statsService.stats?.dailyModelTokens.count ?? 1)
        let months = max(days / 30.0, 1.0)
        let totalSubscriptionCost = months * monthlySubscription
        let saved = totalApiCost - totalSubscriptionCost

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Max Plan Savings")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)

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

                            let multiplier = totalSubscriptionCost > 0 ? totalApiCost / totalSubscriptionCost : 0
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
                                Text(CostCalculator.formatCost(totalApiCost / max(days, 1)))
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
            }
        }
    }
}
