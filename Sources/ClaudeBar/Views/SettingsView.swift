import SwiftUI
import Darwin

struct SettingsView: View {
    @Environment(SettingsService.self) private var settingsService
    @Environment(HookHealthService.self) private var hookHealthService
    @Environment(NotificationService.self) private var notificationService
    @Environment(LaunchAtLoginService.self) private var launchAtLoginService
    @Environment(SessionService.self) private var sessionService
    @Environment(StatsService.self) private var statsService
    @Environment(McpHealthService.self) private var mcpHealthService


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = settingsService.lastError {
                    errorBanner(error)
                }

                SettingsDisplaySection()

                SettingsQuickActionsSection(statsService: statsService)

                SettingsAppSection(launchAtLoginService: launchAtLoginService, statsService: statsService)

                if let settings = settingsService.settings {
                    SettingsNotificationsSection(notificationService: notificationService)
                    SettingsClaudeConfigSection(settingsService: settingsService, settings: settings)
                    SettingsHooksSection(settings: settings, hookHealthService: hookHealthService)
                } else {
                    loadingState
                }

                SettingsMcpSection(mcpHealthService: mcpHealthService)

                Spacer(minLength: 12)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Display & Alerts


    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    private var loadingState: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading settings…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 40)
            Spacer()
        }
    }

    private func maskedValue(_ value: String) -> String {
        guard value.count > 12 else { return String(repeating: "•", count: value.count) }
        return String(repeating: "•", count: value.count - 3) + value.suffix(3)
    }
}

#Preview {
    SettingsView()
        .environment(SettingsService())
        .environment(HookHealthService())
        .environment(NotificationService())
        .environment(LaunchAtLoginService())
        .environment(SessionService())
        .environment(StatsService())
        .environment(McpHealthService())
        .environment(UpdateCheckService())
        .frame(width: 420, height: 480)
}
