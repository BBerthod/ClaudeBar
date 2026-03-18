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

    @State private var selectedTab: Tab = .dashboard

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Label(tab.shortLabel, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView(
                        statsService: statsService,
                        sessionService: sessionService
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
                        hookHealthService: hookHealthService
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
        hookHealthService: HookHealthService()
    )
}
