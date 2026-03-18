import SwiftUI

@main
struct ClaudeBarApp: App {
    @State private var statsService = StatsService()
    @State private var sessionService = SessionService()
    @State private var settingsService = SettingsService()
    @State private var projectService = ProjectService()
    @State private var hookHealthService = HookHealthService()
    @State private var burnRateService = BurnRateService()
    @State private var notificationService = NotificationService()
    @State private var overlayManager = OverlayManager()

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
                hookHealthService: hookHealthService,
                burnRateService: burnRateService,
                notificationService: notificationService,
                overlayManager: overlayManager
            )
            .task {
                projectService.reload(totalCostEstimate: statsService.totalCostEstimate)
                hookHealthService.analyze(settings: settingsService.settings)
                burnRateService.update(statsService: statsService)
                notificationService.checkCostThreshold(currentCost: statsService.todayCostEstimate)
            }
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                    Task { @MainActor in
                        burnRateService.update(statsService: statsService)
                        notificationService.checkCostThreshold(currentCost: statsService.todayCostEstimate)
                        if notificationService.digestPending {
                            notificationService.sendDailyDigest(
                                sessions: statsService.todaySessions,
                                messages: statsService.todayMessages,
                                tokens: statsService.todayTokens,
                                cost: statsService.todayCostEstimate,
                                topProject: projectService.projects.first?.projectName,
                                burnZone: burnRateService.burnRate?.zone
                            )
                            notificationService.digestPending = false
                        }
                    }
                }
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
