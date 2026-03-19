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
    var projectService: ProjectService

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

    // MARK: - Model Breakdown

    private var modelCosts: [(model: String, cost: Double)] {
        guard let stats = statsService.stats else { return [] }
        var costByModel: [String: Double] = [:]
        for day in stats.dailyModelTokens {
            for (modelId, tokenCount) in day.tokensByModel {
                let p = CostCalculator.pricing(for: modelId)
                let mTok = 1_000_000.0
                if let usage = stats.modelUsage[modelId] {
                    let io = usage.inputTokens + usage.outputTokens
                    guard io > 0 else { continue }
                    let frac = Double(tokenCount) / Double(io)
                    let cost = (Double(usage.inputTokens) * frac / mTok * p.inputPerMTok +
                                Double(usage.outputTokens) * frac / mTok * p.outputPerMTok +
                                Double(usage.cacheReadInputTokens) * frac / mTok * p.cacheReadPerMTok +
                                Double(usage.cacheCreationInputTokens) * frac / mTok * p.cacheWritePerMTok)
                    costByModel[StatsService.displayName(for: modelId), default: 0] += cost
                }
            }
        }
        return costByModel.map { (model: $0.key, cost: $0.value) }.sorted { $0.cost > $1.cost }
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
        let specFormatted = specSeconds >= 3600 ? "\(specSeconds / 3600)h \((specSeconds % 3600) / 60)m" : "\(specSeconds / 60)m"

        return GroupBox("Lifetime Stats") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
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
        let sorted = projectService.projects.sorted { $0.estimatedCost > $1.estimatedCost }
        let totalCost = statsService.totalCostEstimate
        let totalMessages = sorted.reduce(0) { $0 + $1.totalMessages }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Project Analytics")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)

                // Summary
                HStack(spacing: 30) {
                    VStack(spacing: 2) {
                        Text("\(sorted.count)")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("projects")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        Text(CostCalculator.formatCost(totalCost))
                            .font(.title)
                            .fontWeight(.bold)
                        Text("total cost")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        Text("\(totalMessages)")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("messages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)

                // Cost distribution chart
                if sorted.count > 1 {
                    GroupBox("Cost Distribution") {
                        Chart(sorted.prefix(10)) { project in
                            BarMark(
                                x: .value("Cost", project.estimatedCost),
                                y: .value("Project", project.projectName)
                            )
                            .foregroundStyle(Color.accentColor.gradient)
                            .annotation(position: .trailing) {
                                Text(CostCalculator.formatCost(project.estimatedCost))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartXAxis(.hidden)
                        .frame(height: CGFloat(min(sorted.count, 10)) * 32)
                        .padding(8)
                    }
                    .padding(.horizontal)
                }

                // Project table
                GroupBox("All Projects") {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Project")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Sessions")
                                .frame(width: 70, alignment: .trailing)
                            Text("Messages")
                                .frame(width: 80, alignment: .trailing)
                            Text("Cost")
                                .frame(width: 90, alignment: .trailing)
                            Text("Share")
                                .frame(width: 60, alignment: .trailing)
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                        Divider()

                        ForEach(sorted) { project in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(project.projectName)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    if let lastActive = project.lastActive {
                                        Text(projectTimeAgo(from: lastActive))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text("\(project.sessionCount)")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .frame(width: 70, alignment: .trailing)

                                Text("\(project.totalMessages)")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .frame(width: 80, alignment: .trailing)

                                Text(CostCalculator.formatCost(project.estimatedCost))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                                    .frame(width: 90, alignment: .trailing)

                                let share = totalCost > 0 ? project.estimatedCost / totalCost * 100 : 0
                                Text(String(format: "%.0f%%", share))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)

                            if project.id != sorted.last?.id {
                                Divider().padding(.horizontal, 8)
                            }
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)
            }
        }
    }

    private func projectTimeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        switch interval {
        case ..<3600:      return "\(Int(interval / 60))m ago"
        case ..<86400:     return "\(Int(interval / 3600))h ago"
        default:           return "\(Int(interval / 86400))d ago"
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
