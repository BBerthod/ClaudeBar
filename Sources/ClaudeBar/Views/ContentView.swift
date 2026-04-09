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
    var desktopWidgetManager: DesktopWidgetManager
    var launchAtLoginService: LaunchAtLoginService
    var mcpHealthService: McpHealthService
    var providerUsageService: ProviderUsageService
    var onRefresh: (() -> Void)?
    var onOpenDashboard: (() -> Void)?

    @State private var selectedTab: Tab = .dashboard

    var body: some View {
        VStack(spacing: 0) {
            // Keyboard shortcuts
            Group {
                Button("") { onRefresh?() }
                    .keyboardShortcut("r", modifiers: .command)
                    .hidden()
                Button("") { selectedTab = .dashboard }
                    .keyboardShortcut("1", modifiers: .command)
                    .hidden()
                Button("") { selectedTab = .history }
                    .keyboardShortcut("2", modifiers: .command)
                    .hidden()
                Button("") { selectedTab = .projects }
                    .keyboardShortcut("3", modifiers: .command)
                    .hidden()
                Button("") { selectedTab = .sessions }
                    .keyboardShortcut("4", modifiers: .command)
                    .hidden()
                Button("") { selectedTab = .settings }
                    .keyboardShortcut("5", modifiers: .command)
                    .hidden()
            }

            // Tab picker + overlay toggle
            HStack(spacing: 6) {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Label(tab.shortLabel, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    desktopWidgetManager.toggle(
                        usageService: usageService,
                        statsService: statsService,
                        sessionService: sessionService
                    )
                } label: {
                    Image(systemName: desktopWidgetManager.isVisible ? "gauge.with.dots.needle.67percent.fill" : "gauge.with.dots.needle.67percent")
                        .font(.system(size: 13))
                        .foregroundStyle(desktopWidgetManager.isVisible ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(desktopWidgetManager.isVisible ? "Hide desktop widget" : "Show desktop widget")

                if let onOpenDashboard {
                    Button(action: onOpenDashboard) {
                        Image(systemName: "macwindow.badge.plus")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open full analytics window")
                }
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
                        liveStatsService: liveStatsService,
                        mcpHealthService: mcpHealthService,
                        providerUsageService: providerUsageService,
                        onRefresh: onRefresh
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
                        notificationService: notificationService,
                        launchAtLoginService: launchAtLoginService,
                        sessionService: sessionService,
                        statsService: statsService,
                        mcpHealthService: mcpHealthService
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        overlayManager: OverlayManager(),
        desktopWidgetManager: DesktopWidgetManager(),
        launchAtLoginService: LaunchAtLoginService(),
        mcpHealthService: McpHealthService(),
        providerUsageService: ProviderUsageService()
    )
}
