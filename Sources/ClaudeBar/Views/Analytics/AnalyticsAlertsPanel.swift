import SwiftUI

struct AnalyticsAlertsPanel: View {
    let statsService: StatsService
    let sessionService: SessionService
    let burnRateService: BurnRateService
    let usageService: UsageService
    let mcpHealthService: McpHealthService

    var body: some View {
        alertsPanel
    }
    struct AlertItem {
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

    var activeAlerts: [AlertItem] {
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
            let secondsRemaining = max(
                fiveHour.resetDate?.timeIntervalSinceNow ?? .greatestFiniteMagnitude,
                0
            )
            let forecast = UsageForecast.limitLabel(
                utilization: fiveHour.utilization,
                elapsedFraction: elapsed,
                secondsRemaining: secondsRemaining
            )
            let forecastSuffix = forecast.map { " — \($0)" } ?? ""
            if elapsed > 0.1 {
                let projected = fiveHour.utilization / elapsed
                if projected > 100 {
                    alerts.append(AlertItem(
                        severity: .critical,
                        icon: "exclamationmark.triangle.fill",
                        title: "Rate Limit Risk",
                        message: "5h window projected to hit \(Int(min(projected, 999)))% at current pace\(forecastSuffix)",
                        timestamp: now
                    ))
                } else if projected > 80 {
                    alerts.append(AlertItem(
                        severity: .warning,
                        icon: "exclamationmark.triangle",
                        title: "Rate Limit Warning",
                        message: "5h window projected to \(Int(projected))%\(forecastSuffix)",
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
            if let date = DateFormatter.isoDate.date(from: lastDate) {
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

}

