import Foundation
import UserNotifications

@Observable
@MainActor
final class NotificationService {
    private(set) var isAuthorized = false
    private(set) var dailyDigestTime: Int = 18 // hour (0–23), default 6 pm
    private(set) var costThreshold: Double = 50.0 // daily cost alert threshold in USD
    private(set) var lastDigestDate: String?
    private(set) var lastThresholdAlertDate: String?
    private var lastUsage80AlertKey: String?
    private var lastUsage95AlertKey: String?

    /// Set to `true` by the timer when the digest hour arrives.
    /// The app can observe this and call `sendDailyDigest(...)` then reset it.
    var digestPending = false

    private var digestTimer: Timer?

    init() {
        startDigestTimer()
        // Delay notification authorization to avoid crash when bundle proxy is unavailable
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.requestAuthorization()
        }
    }

    // MARK: - Authorization

    private func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else {
            // Not running as a proper .app bundle — skip notifications
            isAuthorized = false
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                self.isAuthorized = granted
            }
        }
    }

    // MARK: - Configuration

    func setDailyDigestTime(_ hour: Int) {
        dailyDigestTime = max(0, min(23, hour))
        startDigestTimer()
    }

    func setCostThreshold(_ amount: Double) {
        costThreshold = amount
    }

    // MARK: - Cost Threshold Alert

    func checkCostThreshold(currentCost: Double) {
        let today = todayString()
        guard currentCost >= costThreshold,
              lastThresholdAlertDate != today else { return }

        lastThresholdAlertDate = today
        sendNotification(
            title: "Cost Alert",
            body: "Today's estimated cost has reached \(CostCalculator.formatCost(currentCost)) (threshold: \(CostCalculator.formatCost(costThreshold)))",
            identifier: "cost-threshold-\(today)"
        )
    }

    // MARK: - Usage Threshold Alert

    func checkUsageThreshold(usageService: UsageService) {
        guard let fiveHour = usageService.usage?.fiveHour else { return }
        let utilization = fiveHour.utilization
        let resetKey = fiveHour.resetsAt

        if utilization >= 95 {
            let alertKey = "usage-95-\(resetKey)"
            guard lastUsage95AlertKey != alertKey else { return }
            lastUsage95AlertKey = alertKey
            sendNotification(
                title: "⚠️ Usage Critical — \(Int(utilization))%",
                body: "5-hour window at \(Int(utilization))%. Consider slowing down. Resets: \(fiveHour.timeRemaining ?? "soon")",
                identifier: alertKey
            )
        } else if utilization >= 80 {
            let alertKey = "usage-80-\(resetKey)"
            guard lastUsage80AlertKey != alertKey else { return }
            lastUsage80AlertKey = alertKey
            sendNotification(
                title: "Usage High — \(Int(utilization))%",
                body: "5-hour window at \(Int(utilization))%. Resets: \(fiveHour.timeRemaining ?? "soon")",
                identifier: alertKey
            )
        }
    }

    // MARK: - Daily Digest

    func sendDailyDigest(
        sessions: Int,
        messages: Int,
        tokens: Int,
        cost: Double,
        topProject: String?,
        burnZone: PacingZone?
    ) {
        let today = todayString()
        guard lastDigestDate != today else { return }

        lastDigestDate = today

        var body = "Sessions: \(sessions) | Messages: \(messages) | Tokens: \(tokens.abbreviatedTokenCount) | Cost: \(CostCalculator.formatCost(cost))"
        if let project = topProject {
            body += "\nTop project: \(project)"
        }
        if let zone = burnZone {
            body += " | Pace: \(zone.rawValue)"
        }

        sendNotification(
            title: "Daily Claude Digest",
            body: body,
            identifier: "daily-digest-\(today)"
        )
    }

    // MARK: - Timer

    private func startDigestTimer() {
        digestTimer?.invalidate()
        // Check every minute if it is time for the digest
        digestTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkDigestTime()
            }
        }
    }

    private func checkDigestTime() {
        let hour = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())
        // Trigger within the first minute of the configured digest hour
        if hour == dailyDigestTime && minute == 0 {
            digestPending = true
        }
    }

    // MARK: - Private helpers

    private func sendNotification(title: String, body: String, identifier: String) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: Date())
    }
}
