import SwiftUI

enum Tab: String, CaseIterable {
    case dashboard = "Dashboard"
    case history   = "History"
    case projects  = "Projects"
    case sessions  = "Sessions"
    case settings  = "Settings"

    var icon: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.33percent"
        case .history:   "chart.xyaxis.line"
        case .projects:  "folder"
        case .sessions:  "terminal"
        case .settings:  "gearshape"
        }
    }

    /// Short label used in the segmented control so it fits in 420 pt width.
    var shortLabel: String {
        switch self {
        case .dashboard: "Dash"
        case .history:   "History"
        case .projects:  "Projects"
        case .sessions:  "Sessions"
        case .settings:  "Settings"
        }
    }
}

struct ContentView: View {
    var statsService: StatsService
    var sessionService: SessionService
    var settingsService: SettingsService
    var projectService: ProjectService
    var hookHealthService: HookHealthService
    var burnRateService: BurnRateService
    var notificationService: NotificationService
    var usageService: UsageService
    var liveStatsService: LiveStatsService
    var overlayManager: OverlayManager

    @State private var selectedTab: Tab = .dashboard

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker + overlay toggle
            HStack(spacing: 6) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Label(tab.shortLabel, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    overlayManager.toggle(sessionService: sessionService)
                } label: {
                    Image(systemName: overlayManager.isVisible ? "pip.fill" : "pip")
                        .font(.system(size: 13))
                        .foregroundStyle(overlayManager.isVisible ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(overlayManager.isVisible ? "Hide floating overlay" : "Show floating overlay")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView(
                        statsService: statsService,
                        sessionService: sessionService,
                        burnRateService: burnRateService,
                        usageService: usageService,
                        liveStatsService: liveStatsService
                    )
                case .history:
                    HistoryView(statsService: statsService)
                case .projects:
                    ProjectsView(
                        projectService: projectService,
                        statsService: statsService
                    )
                case .sessions:
                    SessionsView(sessionService: sessionService)
                case .settings:
                    SettingsView(
                        settingsService: settingsService,
                        hookHealthService: hookHealthService,
                        notificationService: notificationService
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 420, height: 520)
    }
}

#Preview {
    ContentView(
        statsService: StatsService(),
        sessionService: SessionService(),
        settingsService: SettingsService(),
        projectService: ProjectService(),
        hookHealthService: HookHealthService(),
        burnRateService: BurnRateService(),
        notificationService: NotificationService(),
        usageService: UsageService(),
        liveStatsService: LiveStatsService(),
        overlayManager: OverlayManager()
    )
}
