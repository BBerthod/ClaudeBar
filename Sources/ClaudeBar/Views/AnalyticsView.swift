import SwiftUI
import Charts
import AppKit

enum AnalyticsSection: String, CaseIterable {
    case alerts   = "Alerts"
    case trends   = "Trends"
    case projects = "Projects"
    case sessions = "Sessions"
    case models   = "Models"
    case savings  = "Savings"
    case system   = "System"

    var icon: String {
        switch self {
        case .alerts:   "bell.badge"
        case .trends:   "chart.line.uptrend.xyaxis"
        case .projects: "folder"
        case .sessions: "terminal"
        case .models:   "chart.pie"
        case .savings:  "banknote"
        case .system:   "cpu"
        }
    }
}

struct AnalyticsView: View {
    @Environment(StatsService.self) private var statsService
    @Environment(SessionService.self) private var sessionService
    @Environment(BurnRateService.self) private var burnRateService
    @Environment(UsageService.self) private var usageService
    @Environment(LiveStatsService.self) private var liveStatsService
    @Environment(McpHealthService.self) private var mcpHealthService
    @Environment(ProjectService.self) private var projectService
    @Environment(YearlyHistoryService.self) private var yearlyHistoryService
    @Environment(OmlxMonitorService.self) private var omlxMonitorService
    @Environment(ProviderUsageService.self) private var providerUsageService

    @State private var selectedSection: AnalyticsSection = .alerts

    // MARK: - Badge counts

    private var alertCount: Int { alertsPanel.activeAlerts.count }
    private var projectCount: Int { projectService.projects.count }
    private var sessionCount: Int { sessionService.activeSessions.count }


    private var alertsPanel: AnalyticsAlertsPanel {
        AnalyticsAlertsPanel(
            statsService: statsService,
            sessionService: sessionService,
            burnRateService: burnRateService,
            usageService: usageService,
            mcpHealthService: mcpHealthService
        )
    }

    private var trendsPanel: AnalyticsTrendsPanel {
        AnalyticsTrendsPanel(
            statsService: statsService,
            sessionService: sessionService,
            burnRateService: burnRateService,
            liveStatsService: liveStatsService
        )
    }

    private var projectsPanel: AnalyticsProjectsPanel {
        AnalyticsProjectsPanel(
            statsService: statsService,
            projectService: projectService
        )
    }

    private var sessionsPanel: AnalyticsSessionsPanel {
        AnalyticsSessionsPanel(sessionService: sessionService)
    }

    private var savingsPanel: AnalyticsSavingsPanel {
        AnalyticsSavingsPanel(
            statsService: statsService,
            yearlyHistoryService: yearlyHistoryService
        )
    }

    private var systemPanel: AnalyticsSystemPanel {
        AnalyticsSystemPanel(
            statsService: statsService,
            sessionService: sessionService,
            usageService: usageService,
            mcpHealthService: mcpHealthService,
            omlxMonitorService: omlxMonitorService,
            providerUsageService: providerUsageService
        )
    }

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
            case .models:   ModelsBreakdownView(breakdown: yearlyHistoryService.last30DaysModelBreakdown)
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
        let hasCritical = alertsPanel.activeAlerts.contains { $0.severity == .critical }
        return hasCritical ? .red : .orange
    }

    // MARK: - Alerts Panel

}
