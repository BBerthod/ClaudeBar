import SwiftUI

@main
struct ClaudeBarApp: App {
    @State private var statsService = StatsService()
    @State private var sessionService = SessionService()
    @State private var settingsService = SettingsService()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(
                statsService: statsService,
                sessionService: sessionService,
                settingsService: settingsService
            )
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
