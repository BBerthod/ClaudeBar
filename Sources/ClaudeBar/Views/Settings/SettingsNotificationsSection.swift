import SwiftUI

struct SettingsNotificationsSection: View {
    let notificationService: NotificationService

    @AppStorage("claudebar.alertThreshold1Enabled") private var threshold1Enabled: Bool = true
    @AppStorage("claudebar.alertThreshold1Value")   private var threshold1Value: Double = 0.25
    @AppStorage("claudebar.alertThreshold2Enabled") private var threshold2Enabled: Bool = true
    @AppStorage("claudebar.alertThreshold2Value")   private var threshold2Value: Double = 0.50
    @AppStorage("claudebar.alertThreshold3Enabled") private var threshold3Enabled: Bool = true
    @AppStorage("claudebar.alertThreshold3Value")   private var threshold3Value: Double = 0.75
    @AppStorage("claudebar.alertThreshold4Enabled") private var threshold4Enabled: Bool = true
    @AppStorage("claudebar.alertThreshold4Value")   private var threshold4Value: Double = 0.90

    var body: some View {
        Group {
            notificationsSection()
            rateLimitAlertsSection()
        }
    }
    @ViewBuilder
    private func notificationsSection() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Authorization status
                HStack {
                    Label(
                        "Notifications",
                        systemImage: notificationService.isAuthorized ? "bell.badge" : "bell.slash"
                    )
                    .font(.subheadline)
                    Spacer()
                    Text(notificationService.isAuthorized ? "Authorized" : "Not authorized")
                        .font(.caption)
                        .foregroundStyle(notificationService.isAuthorized ? .green : .red)
                }

                Divider()

                // Daily digest time
                HStack {
                    Label("Daily digest", systemImage: "clock")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { notificationService.dailyDigestTime },
                        set: { notificationService.setDailyDigestTime($0) }
                    )) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formatHour(hour)).tag(hour)
                        }
                    }
                    .frame(width: 100)
                }

                Divider()

                // Sound alerts
                Toggle(isOn: Binding(
                    get: { notificationService.soundEnabled },
                    set: { notificationService.setSoundEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sound Alerts")
                            .font(.subheadline)
                        Text("Play a sound when usage thresholds are crossed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
        } label: {
            SettingsSectionLabel("Notifications")
        }
        .padding(.horizontal, 12)
    }

    private func formatHour(_ hour: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return f.string(from: date)
    }

    // MARK: - Rate Limit Alerts

    @ViewBuilder
    private func rateLimitAlertsSection() -> some View {
        GroupBox("Rate Limit Alerts") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notify when the 5-hour window reaches:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                thresholdRow(enabled: $threshold1Enabled, value: $threshold1Value)
                Divider()
                thresholdRow(enabled: $threshold2Enabled, value: $threshold2Value)
                Divider()
                thresholdRow(enabled: $threshold3Enabled, value: $threshold3Value)
                Divider()
                thresholdRow(enabled: $threshold4Enabled, value: $threshold4Value)
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func thresholdRow(enabled: Binding<Bool>, value: Binding<Double>) -> some View {
        HStack {
            Toggle("", isOn: enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            Text("At \(Int(value.wrappedValue * 100))%")
                .frame(width: 44, alignment: .leading)
            Spacer()
            Stepper("", value: value, in: 0.05...0.95, step: 0.05)
                .labelsHidden()
                .frame(width: 80)
        }
    }

}

