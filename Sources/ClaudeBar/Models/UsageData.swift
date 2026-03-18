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

    /// Parsed reset date.
    var resetDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: resetsAt) ?? {
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            return f2.date(from: resetsAt)
        }()
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
