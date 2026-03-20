import Foundation
import UserNotifications

@Observable
@MainActor
final class NotificationService {
    private(set) var isAuthorized = false
    private(set) var dailyDigestTime: Int = 18 // hour (0–23), default 6 pm
    private(set) var lastDigestDate: String?
    private var lastUsage80AlertKey: String?
    private var lastUsage95AlertKey: String?

    /// Set to `true` by the timer when the digest hour arrives.
    /// The app can observe this and call `sendDailyDigest(...)` then reset it.
    var digestPending = false

    private var digestTimer: Timer?

    // MARK: - UserDefaults keys

    private enum DefaultsKey {
        static let dailyDigestTime = "claudebar.dailyDigestTime"
    }

    init() {
        // Load persisted preferences before starting the timer
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.dailyDigestTime) != nil {
            dailyDigestTime = defaults.integer(forKey: DefaultsKey.dailyDigestTime)
        }

        startDigestTimer()
        // Delay notification authorization to avoid crash when bundle proxy is unavailable
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.requestAuthorization()
        }
    }

    /// When `true`, notifications are sent via `osascript` instead of UNUserNotificationCenter.
    /// SPM executables have no bundle identifier, so UNUserNotificationCenter cannot be used.
    private var usesOsascriptFallback = false

    // MARK: - Authorization

    private func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else {
            // SPM executable — use osascript fallback (always works)
            usesOsascriptFallback = true
            isAuthorized = true
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
        UserDefaults.standard.set(dailyDigestTime, forKey: DefaultsKey.dailyDigestTime)
        startDigestTimer()
    }

    // MARK: - Usage Threshold Alert

    /// Fires a notification at 80 % and/or 95 % of the 5-hour rate-limit window.
    ///
    /// - Parameters:
    ///   - fiveHourUtilization: Current utilization expressed as a value from 0 to 100.
    ///   - resetKey: A string that uniquely identifies the current reset window (e.g. the
    ///     ISO timestamp of the window's reset time). Used to deduplicate alerts so only one
    ///     notification fires per threshold per window.
    func checkUsageThreshold(fiveHourUtilization: Double, resetKey: String) {
        if fiveHourUtilization >= 95 {
            let alertKey = "usage-95-\(resetKey)"
            guard lastUsage95AlertKey != alertKey else { return }
            lastUsage95AlertKey = alertKey
            sendNotification(
                title: "Rate Limit Critical",
                body: "5-hour window at \(Int(fiveHourUtilization))% utilization",
                identifier: alertKey
            )
        } else if fiveHourUtilization >= 80 {
            let alertKey = "usage-80-\(resetKey)"
            guard lastUsage80AlertKey != alertKey else { return }
            lastUsage80AlertKey = alertKey
            sendNotification(
                title: "Rate Limit Warning",
                body: "5-hour window at \(Int(fiveHourUtilization))% utilization",
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

        if usesOsascriptFallback {
            sendViaOsascript(title: title, body: body)
            return
        }

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

    private func sendViaOsascript(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // Pass title/body via ARGV to avoid shell injection.
        process.arguments = [
            "-e", "on run argv",
            "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
            "-e", "end run",
            "--", title, body
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func todayString() -> String {
        DateFormatter.isoDate.string(from: Date())
    }
}
