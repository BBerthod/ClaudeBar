import SwiftUI

enum Tab: String, CaseIterable {
    case dashboard = "Dashboard"
    case history = "History"
    case sessions = "Sessions"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.33percent"
        case .history:   "chart.xyaxis.line"
        case .sessions:  "terminal"
        case .settings:  "gearshape"
        }
    }
}

struct ContentView: View {
    var statsService: StatsService
    var sessionService: SessionService
    var settingsService: SettingsService

    @State private var selectedTab: Tab = .dashboard

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
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
                case .sessions:
                    SessionsView(sessionService: sessionService)
                case .settings:
                    SettingsView(settingsService: settingsService)
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
        settingsService: SettingsService()
    )
}
