import SwiftUI

@main
struct ClaudeBarApp: App {
    @State private var statsService = StatsService()
    @State private var sessionService = SessionService()
    @State private var settingsService = SettingsService()
    @State private var projectService = ProjectService()
    @State private var hookHealthService = HookHealthService()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(
                statsService: statsService,
                sessionService: sessionService,
                settingsService: settingsService,
                projectService: projectService,
                hookHealthService: hookHealthService
            )
            .task {
                projectService.reload(totalCostEstimate: statsService.totalCostEstimate)
                hookHealthService.analyze(settings: settingsService.settings)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                if statsService.todayTokens > 0 {
                    Text(statsService.todayTokens.abbreviatedTokenCount)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
