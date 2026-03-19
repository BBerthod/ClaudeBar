import SwiftUI
import Charts
import AppKit

enum AnalyticsSection: String, CaseIterable {
    case alerts   = "Alerts"
    case trends   = "Trends"
    case projects = "Projects"
    case sessions = "Sessions"
    case savings  = "Savings"
    case system   = "System"

    var icon: String {
        switch self {
        case .alerts:   "bell.badge"
        case .trends:   "chart.line.uptrend.xyaxis"
        case .projects: "folder"
        case .sessions: "terminal"
        case .savings:  "banknote"
        case .system:   "cpu"
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

    // MARK: - Badge counts

    private var alertCount: Int { activeAlerts.count }
    private var projectCount: Int { projectService.projects.count }
    private var sessionCount: Int { sessionService.activeSessions.count }

    var body: some View {
        NavigationSplitView {
            List(AnalyticsSection.allCases, id: \.self, selection: $selectedSection) { section in
                Label {
                    HStack {
                        Text(section.rawValue)
                        Spacer()
                        badgeView(for: section)
                    }
                } icon: {
                    Image(systemName: section.icon)
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 210)
        } detail: {
            switch selectedSection {
            case .alerts:   alertsPanel
            case .trends:   trendsPanel
            case .projects: projectsPanel
            case .sessions: sessionsPanel
            case .savings:  savingsPanel
            case .system:   systemPanel
            }
        }
    }

    @ViewBuilder
    private func badgeView(for section: AnalyticsSection) -> some View {
        switch section {
        case .alerts where alertCount > 0:
            badgePill("\(alertCount)", color: alertCount > 0 ? criticalOrWarningColor : .blue)
        case .projects where projectCount > 0:
            badgePill("\(projectCount)", color: .secondary)
        case .sessions where sessionCount > 0:
            badgePill("\(sessionCount)", color: .green)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.8))
            .clipShape(Capsule())
    }

    private var criticalOrWarningColor: Color {
        let hasCritical = activeAlerts.contains { $0.severity == .critical }
        return hasCritical ? .red : .orange
    }

    // MARK: - Alerts Panel

    private struct AlertItem {
        let severity: AlertSeverity
        let icon: String
        let title: String
        let message: String
        let timestamp: Date

        enum AlertSeverity: Int, Comparable {
            case critical = 0
            case warning  = 1
            case info     = 2

            static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }
    }

    private var activeAlerts: [AlertItem] {
        var alerts: [AlertItem] = []
        let now = Date()

        // Context window alerts
        for session in sessionService.activeSessions {
            if let ctx = sessionService.contextEstimates[session.sessionId], ctx > 0.8 {
                alerts.append(AlertItem(
                    severity: ctx > 0.95 ? .critical : .warning,
                    icon: "gauge.with.dots.needle.100percent",
                    title: "Context \(Int(ctx * 100))%",
                    message: "\(session.projectName) is running out of context window",
                    timestamp: now
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
                        message: "5h window projected to hit \(Int(min(projected, 999)))% at current pace",
                        timestamp: now
                    ))
                } else if projected > 80 {
                    alerts.append(AlertItem(
                        severity: .warning,
                        icon: "exclamationmark.triangle",
                        title: "Rate Limit Warning",
                        message: "5h window projected to \(Int(projected))%",
                        timestamp: now
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
                message: "Today's usage is \(Int(rate.percentOfAverage * 100))% of your daily average",
                timestamp: now
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
                        message: "Last updated \(days) days ago — Claude Code will refresh it automatically",
                        timestamp: date
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
                    message: err,
                    timestamp: now
                ))
            }
        }

        return alerts.sorted { $0.severity < $1.severity }
    }

    private var alertsPanel: some View {
        let criticalCount = activeAlerts.filter { $0.severity == .critical }.count
        let warningCount  = activeAlerts.filter { $0.severity == .warning }.count
        let infoCount     = activeAlerts.filter { $0.severity == .info }.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header row with refresh button
                HStack {
                    Text("Smart Alerts")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    Button {
                        mcpHealthService.checkAll()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .disabled(mcpHealthService.isChecking)
                }
                .padding(.horizontal)
                .padding(.top)

                // Summary bar
                if !activeAlerts.isEmpty {
                    HStack(spacing: 16) {
                        if criticalCount > 0 {
                            alertSumBadge("\(criticalCount) critical", color: .red)
                        }
                        if warningCount > 0 {
                            alertSumBadge("\(warningCount) warning", color: .orange)
                        }
                        if infoCount > 0 {
                            alertSumBadge("\(infoCount) info", color: .blue)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                if activeAlerts.isEmpty {
                    ContentUnavailableView(
                        "All Clear",
                        systemImage: "checkmark.shield",
                        description: Text("No alerts right now.")
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(Array(activeAlerts.enumerated()), id: \.offset) { _, alert in
                        alertRow(alert)
                            .padding(.horizontal)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func alertSumBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.5))
    }

    @ViewBuilder
    private func alertRow(_ alert: AlertItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: alert.icon)
                .font(.title3)
                .foregroundStyle(alertColor(alert.severity))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(alert.title)
                        .font(.headline)
                    Spacer()
                    Text(alert.timestamp.formattedTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(alert.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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

    // MARK: - Shared date formatter

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

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
        }
    }

    // MARK: - Projects Panel

    @State private var projectSearch: String = ""
    @State private var copiedProjectPath: String?

    private var filteredProjects: [ProjectStats] {
        let sorted = projectService.projects.sorted { $0.estimatedCost > $1.estimatedCost }
        guard !projectSearch.isEmpty else { return sorted }
        return sorted.filter {
            $0.projectName.localizedCaseInsensitiveContains(projectSearch) ||
            $0.projectPath.localizedCaseInsensitiveContains(projectSearch)
        }
    }

    private var projectsPanel: some View {
        let projects = filteredProjects
        let totalCost = statsService.totalCostEstimate
        let totalMessages = projects.reduce(0) { $0 + $1.totalMessages }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Project Analytics")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)

                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter projects…", text: $projectSearch)
                        .textFieldStyle(.plain)
                    if !projectSearch.isEmpty {
                        Button {
                            projectSearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)

                // Summary
                HStack(spacing: 30) {
                    VStack(spacing: 2) {
                        Text("\(projects.count)")
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
                if projects.count > 1 {
                    GroupBox("Cost Distribution") {
                        Chart(projects.prefix(10)) { project in
                            BarMark(
                                x: .value("Cost", project.estimatedCost),
                                y: .value("Project", project.projectName)
                            )
                            .foregroundStyle(projectCostColor(project.estimatedCost).gradient)
                            .annotation(position: .trailing) {
                                Text(CostCalculator.formatCost(project.estimatedCost))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartXAxis(.hidden)
                        .frame(height: CGFloat(min(projects.count, 10)) * 32)
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
                                .frame(width: 65, alignment: .trailing)
                            Text("Messages")
                                .frame(width: 75, alignment: .trailing)
                            Text("Cost")
                                .frame(width: 80, alignment: .trailing)
                            Text("ROI")
                                .frame(width: 70, alignment: .trailing)
                            Text("Share")
                                .frame(width: 55, alignment: .trailing)
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                        Divider()

                        ForEach(projects) { project in
                            projectRow(project, totalCost: totalCost)

                            if project.id != projects.last?.id {
                                Divider().padding(.horizontal, 8)
                            }
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                if let copied = copiedProjectPath {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Copied: \(copied)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ project: ProjectStats, totalCost: Double) -> some View {
        let devHours = HumanCostCalculator.estimateHumanHours(
            messages: project.totalMessages,
            toolCalls: 0
        )
        let share = totalCost > 0 ? project.estimatedCost / totalCost * 100 : 0

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
                .frame(width: 65, alignment: .trailing)

            Text("\(project.totalMessages)")
                .font(.subheadline)
                .monospacedDigit()
                .frame(width: 75, alignment: .trailing)

            Text(CostCalculator.formatCost(project.estimatedCost))
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(projectCostColor(project.estimatedCost))
                .frame(width: 80, alignment: .trailing)

            Text(HumanCostCalculator.formatHours(devHours))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.blue)
                .frame(width: 70, alignment: .trailing)
                .help("Estimated equivalent dev time")

            Text(String(format: "%.0f%%", share))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 55, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.projectPath, forType: .string)
            withAnimation {
                copiedProjectPath = project.projectPath
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    if copiedProjectPath == project.projectPath {
                        copiedProjectPath = nil
                    }
                }
            }
        }
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func projectCostColor(_ cost: Double) -> Color {
        switch cost {
        case ..<100:   return .green
        case ..<1000:  return .yellow
        case ..<5000:  return .orange
        default:       return .red
        }
    }

    private func projectTimeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        switch interval {
        case ..<3600:  return "\(Int(interval / 60))m ago"
        case ..<86400: return "\(Int(interval / 3600))h ago"
        default:       return "\(Int(interval / 86400))d ago"
        }
    }

    // MARK: - Sessions Panel

    private var totalActiveTime: TimeInterval {
        sessionService.activeSessions.reduce(0) { $0 + $1.duration }
    }

    private var sessionsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sessions")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)

                // Active sessions
                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Label("Active Sessions", systemImage: "circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .labelStyle(.titleAndIcon)
                            Image(systemName: "circle.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.green)
                                .offset(x: -16, y: -4)

                            Spacer()

                            if !sessionService.activeSessions.isEmpty {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("\(sessionService.activeSessions.count) running")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                    Text("total: \(totalActiveTime.formattedDuration)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)

                        if sessionService.activeSessions.isEmpty {
                            Text("No active sessions")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 12)
                        } else {
                            Divider().padding(.horizontal, 8)

                            ForEach(sessionService.activeSessions) { session in
                                activeSessionRow(session)

                                if session.id != sessionService.activeSessions.last?.id {
                                    Divider().padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                // Recent sessions
                GroupBox("Recent Sessions (last 20)") {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Summary")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Project")
                                .frame(width: 120, alignment: .trailing)
                            Text("Messages")
                                .frame(width: 75, alignment: .trailing)
                            Text("Branch")
                                .frame(width: 100, alignment: .trailing)
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                        Divider()

                        ForEach(sessionService.recentSessions.prefix(20)) { entry in
                            recentSessionRow(entry)

                            if entry.id != sessionService.recentSessions.prefix(20).last?.id {
                                Divider().padding(.horizontal, 8)
                            }
                        }

                        if sessionService.recentSessions.isEmpty {
                            Text("No recent sessions found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func activeSessionRow(_ session: ActiveSession) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(session.cwd)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(session.duration.formattedDuration)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                Text("PID \(session.pid)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let ctx = sessionService.contextEstimates[session.sessionId], ctx > 0 {
                ContextGauge(percentage: ctx, compact: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            ProcessHelper.focusTerminal(forChildPID: session.pid)
        }
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    @ViewBuilder
    private func recentSessionRow(_ entry: SessionIndexEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                if let summary = entry.summary ?? entry.firstPrompt {
                    Text(summary)
                        .font(.subheadline)
                        .lineLimit(1)
                } else {
                    Text(entry.sessionId.prefix(12) + "…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let modStr = entry.modified {
                    Text(modStr.prefix(10))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.projectName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 120, alignment: .trailing)

            Text("\(entry.messageCount ?? 0)")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 75, alignment: .trailing)

            Text(entry.gitBranch ?? "—")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    // MARK: - Savings Panel

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
            guard Self.isoDateFormatter.date(from: day.date) != nil else { continue }
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

    private var systemPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("System")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)

                // App info
                GroupBox("ClaudeBar") {
                    VStack(spacing: 0) {
                        systemInfoRow("Version", value: "1.0.0")
                        Divider().padding(.horizontal, 8)
                        systemInfoRow("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                        Divider().padding(.horizontal, 8)
                        systemInfoRow("Memory", value: memoryUsageString())
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                // OAuth / plan status
                GroupBox("Account") {
                    VStack(spacing: 0) {
                        systemInfoRow("Plan", value: usageService.plan.displayName)
                        Divider().padding(.horizontal, 8)
                        systemInfoRow("Rate Tier", value: usageService.tier.displayName)
                        Divider().padding(.horizontal, 8)
                        systemInfoRow(
                            "Token Status",
                            value: tokenStatusString(),
                            valueColor: tokenStatusColor()
                        )
                        if let lastFetched = usageService.lastFetched {
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Last API Fetch", value: lastFetched.formattedTime)
                        }
                        if let lastError = usageService.lastError {
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("API Error", value: lastError, valueColor: .red)
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                // Stats cache info
                GroupBox("Stats Cache") {
                    VStack(spacing: 0) {
                        if let stats = statsService.stats {
                            systemInfoRow("Last Computed", value: stats.lastComputedDate)
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Staleness", value: statsCacheStaleness(stats.lastComputedDate), valueColor: statsCacheStalenessColor(stats.lastComputedDate))
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Days of Data", value: "\(stats.dailyModelTokens.count) days")
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Total Sessions", value: "\(stats.totalSessions)")
                        } else {
                            Text("Stats cache not loaded")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                        }
                        if let lastError = statsService.lastError {
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Load Error", value: lastError, valueColor: .red)
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                // MCP servers
                GroupBox("MCP Servers") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("\(mcpHealthService.servers.count) configured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                mcpHealthService.checkAll()
                            } label: {
                                Label(
                                    mcpHealthService.isChecking ? "Checking…" : "Check All",
                                    systemImage: "arrow.clockwise"
                                )
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(mcpHealthService.isChecking)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                        if mcpHealthService.servers.isEmpty {
                            Text("No MCP servers configured")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                        } else {
                            Divider()

                            ForEach(mcpHealthService.servers) { server in
                                mcpServerRow(server)

                                if server.id != mcpHealthService.servers.last?.id {
                                    Divider().padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                // Quick actions
                GroupBox("Quick Actions") {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        quickActionButton(
                            "settings.json",
                            icon: "gear",
                            path: NSString(string: "~/.claude/settings.json").expandingTildeInPath
                        )
                        quickActionButton(
                            ".claude.json",
                            icon: "doc.badge.gearshape",
                            path: NSString(string: "~/.claude.json").expandingTildeInPath
                        )
                        quickActionButton(
                            "~/.claude folder",
                            icon: "folder.badge.person.crop",
                            path: NSString(string: "~/.claude").expandingTildeInPath
                        )
                        quickActionButton(
                            "Projects folder",
                            icon: "folder.fill.badge.person.crop",
                            path: NSString(string: "~/.claude/projects").expandingTildeInPath
                        )
                        Button {
                            launchClaudeInTerminal()
                        } label: {
                            Label("Launch Claude", systemImage: "terminal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            launchClaudeWithContinue()
                        } label: {
                            Label("claude --continue", systemImage: "arrow.uturn.backward.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func systemInfoRow(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func mcpServerRow(_ server: McpServerInfo) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(mcpStatusColor(server.status))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(server.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(server.endpoint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(server.status.label)
                .font(.caption)
                .foregroundStyle(mcpStatusColor(server.status))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(mcpStatusColor(server.status).opacity(0.1))
                .clipShape(Capsule())

            Text(server.type)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func mcpStatusColor(_ status: McpServerInfo.McpStatus) -> Color {
        switch status {
        case .healthy:    return .green
        case .unhealthy:  return .red
        case .checking:   return .orange
        case .unknown:    return .secondary
        }
    }

    @ViewBuilder
    private func quickActionButton(_ label: String, icon: String, path: String) -> some View {
        Button {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.open(url)
        } label: {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func launchClaudeInTerminal() {
        launchClaude(flags: [])
    }

    private func launchClaudeWithContinue() {
        launchClaude(flags: ["--continue"])
    }

    /// Launches claude in Terminal.app using the safe ARGV pattern.
    private func launchClaude(flags: [String]) {
        var parts = ["claude"]
        parts.append(contentsOf: flags)
        let command = parts.joined(separator: " ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "on run argv",
            "-e", "tell application \"Terminal\"",
            "-e", "    activate",
            "-e", "    do script (item 1 of argv)",
            "-e", "end tell",
            "-e", "end run",
            "--", command
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: - System helpers

    private func memoryUsageString() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return "Unknown" }
        let megabytes = Double(info.resident_size) / (1024 * 1024)
        return String(format: "%.1f MB", megabytes)
    }

    private func tokenStatusString() -> String {
        guard usageService.lastFetched != nil else { return "No token / not fetched" }
        if let error = usageService.lastError {
            if error.contains("401") || error.contains("expired") { return "Expired" }
            return "Error: \(error)"
        }
        return "Valid"
    }

    private func tokenStatusColor() -> Color {
        guard usageService.lastFetched != nil else { return .secondary }
        if let error = usageService.lastError {
            if error.contains("401") || error.contains("expired") { return .red }
            return .orange
        }
        return .green
    }

    private func statsCacheStaleness(_ dateString: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let date = f.date(from: dateString) else { return "Unknown" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return "Fresh (today)" }
        if days == 1 { return "1 day old" }
        return "\(days) days old"
    }

    private func statsCacheStalenessColor(_ dateString: String) -> Color {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let date = f.date(from: dateString) else { return .secondary }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return .green }
        if days == 1 { return .orange }
        return .red
    }
}

