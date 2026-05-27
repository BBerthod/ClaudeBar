import Foundation

// MARK: - API Response

/// Decoded from `GET https://api.anthropic.com/api/oauth/usage`.
struct UsageResponse: Codable, Sendable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

struct UsageWindow: Codable, Sendable {
    /// Utilization percentage (0–100).
    let utilization: Double
    /// ISO-8601 reset timestamp.
    let resetsAt: String

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parsed reset date.
    var resetDate: Date? {
        UsageWindow.isoFormatterFractional.date(from: resetsAt)
            ?? UsageWindow.isoFormatterStandard.date(from: resetsAt)
    }

    /// Time remaining until reset, formatted.
    var timeRemaining: String? {
        guard let reset = resetDate else { return nil }
        let remaining = reset.timeIntervalSince(Date())
        guard remaining > 0 else { return "resetting…" }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct ExtraUsage: Codable, Sendable {
    let isEnabled: Bool
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }
}

// MARK: - Keychain Credentials

/// Structure stored in macOS Keychain under "Claude Code-credentials".
struct KeychainCredentials: Codable, Sendable {
    let claudeAiOauth: OAuthTokens

    struct OAuthTokens: Codable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int  // Unix timestamp in milliseconds
        let scopes: [String]
        let subscriptionType: String?
        let rateLimitTier: String?

        /// Whether the token has expired.
        var isExpired: Bool {
            Date().timeIntervalSince1970 * 1000 > Double(expiresAt)
        }
    }
}

// MARK: - Plan Info

enum SubscriptionPlan: String, Sendable {
    case free = "free"
    case pro = "pro"
    case max = "max"
    case team = "team"
    case enterprise = "enterprise"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .free: "Free"
        case .pro: "Pro"
        case .max: "Max"
        case .team: "Team"
        case .enterprise: "Enterprise"
        case .unknown: "Unknown"
        }
    }
}

enum RateLimitTier: Sendable {
    case max5x
    case max20x
    case pro
    case other(String)

    init(raw: String?) {
        guard let raw else { self = .other("unknown"); return }
        let lower = raw.lowercased()
        if lower.contains("max_20x") { self = .max20x }
        else if lower.contains("max_5x") { self = .max5x }
        else if lower.contains("pro") { self = .pro }
        else { self = .other(raw) }
    }

    var displayName: String {
        switch self {
        case .max20x: "Max 20x"
        case .max5x: "Max 5x"
        case .pro: "Pro"
        case .other(let s): s
        }
    }
}

// MARK: - Pace

/// 6-tier pace system based on projected end-of-window usage.
enum PaceLevel: String, Sendable, CaseIterable {
    case comfortable = "Comfortable"
    case onTrack = "On Track"
    case warming = "Warming"
    case pressing = "Pressing"
    case critical = "Critical"
    case runaway = "Runaway"

    init(utilization: Double, elapsedFraction: Double) {
        guard elapsedFraction > 0.05 else {
            // Too early to project — assume comfortable
            self = .comfortable
            return
        }
        let projected = utilization / elapsedFraction
        switch projected {
        case ..<50:     self = .comfortable
        case 50..<75:   self = .onTrack
        case 75..<90:   self = .warming
        case 90..<100:  self = .pressing
        case 100..<120: self = .critical
        default:        self = .runaway
        }
    }
}

enum UsageForecast {
    /// Linear projection of seconds until utilization reaches 100%, given current
    /// utilization (0-100) and the fraction of the 5h window elapsed (0-1).
    /// Returns nil when no meaningful forecast (utilization ~0, or elapsed ~0).
    /// windowSeconds defaults to 5h.
    static func secondsToLimit(
        utilization: Double,
        elapsedFraction: Double,
        windowSeconds: Double = 5 * 3600
    ) -> TimeInterval? {
        guard utilization > 1, elapsedFraction > 0.02, utilization < 100 else { return nil }
        let elapsedSeconds = elapsedFraction * windowSeconds
        let ratePerSecond = utilization / elapsedSeconds
        guard ratePerSecond > 0 else { return nil }
        return (100 - utilization) / ratePerSecond
    }

    /// Human label, e.g. "≈ limite dans 1h38" or "pas avant le reset" when the
    /// projected time-to-limit exceeds the time left in the window.
    static func limitLabel(
        utilization: Double,
        elapsedFraction: Double,
        secondsRemaining: TimeInterval
    ) -> String? {
        guard let seconds = secondsToLimit(
            utilization: utilization,
            elapsedFraction: elapsedFraction
        ) else { return nil }
        if seconds >= secondsRemaining { return "pas avant le reset" }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "≈ limite dans \(h)h\(String(format: "%02d", m))" : "≈ limite dans \(m)min"
    }

    /// True when the projected time-to-limit is real (hits before the window resets)
    /// AND under `threshold` seconds (default 2h) — i.e. the user should be warned urgently.
    static func isUrgent(
        utilization: Double,
        elapsedFraction: Double,
        secondsRemaining: TimeInterval,
        threshold: TimeInterval = 2 * 3600
    ) -> Bool {
        guard let seconds = secondsToLimit(
            utilization: utilization,
            elapsedFraction: elapsedFraction
        ) else { return false }
        return seconds < secondsRemaining && seconds < threshold
    }
}
