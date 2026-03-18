import Foundation

// MARK: - DailyActivity

/// One entry from `dailyActivity` in stats-cache.json.
struct DailyActivity: Codable, Sendable, Identifiable {
    let date: String          // "YYYY-MM-DD"
    let messageCount: Int
    let sessionCount: Int
    let toolCallCount: Int

    /// Use date string as the stable identifier (one entry per day).
    var id: String { date }
}

// MARK: - DailyModelTokens

/// One entry from `dailyModelTokens` in stats-cache.json.
struct DailyModelTokens: Codable, Sendable {
    let date: String          // "YYYY-MM-DD"
    /// Keys are model ID strings, values are token counts.
    let tokensByModel: [String: Int]
}

// MARK: - ModelUsageEntry

/// Usage breakdown for a single model in `modelUsage`.
struct ModelUsageEntry: Codable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadInputTokens: Int
    let cacheCreationInputTokens: Int
    let webSearchRequests: Int
    let costUSD: Double
    let contextWindow: Int
    let maxOutputTokens: Int

    /// Total tokens (input + output + cache reads + cache writes).
    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens
    }
}

// MARK: - LongestSession

struct LongestSession: Codable, Sendable {
    let sessionId: String
    /// Duration in nanoseconds (as stored in the JSON).
    let duration: Int
    let messageCount: Int
    let timestamp: String     // ISO-8601
}

// MARK: - StatsCache

/// Root object decoded from `~/.claude/stats-cache.json`.
struct StatsCache: Codable, Sendable {
    let version: Int
    let lastComputedDate: String   // "YYYY-MM-DD"
    let dailyActivity: [DailyActivity]
    let dailyModelTokens: [DailyModelTokens]
    /// Keys are model ID strings.
    let modelUsage: [String: ModelUsageEntry]
    let totalSessions: Int
    let totalMessages: Int
    let longestSession: LongestSession?
    let firstSessionDate: String?  // ISO-8601
    /// Keys are hour strings "0"–"23", values are message counts.
    let hourCounts: [String: Int]
    let totalSpeculationTimeSavedMs: Int?

    // MARK: Computed properties

    /// Returns today's DailyActivity entry, or nil if not found.
    var todayActivity: DailyActivity? {
        let today = Self.todayString()
        return dailyActivity.first { $0.date == today }
    }

    /// Returns today's DailyModelTokens entry, or nil if not found.
    var todayModelTokens: DailyModelTokens? {
        let today = Self.todayString()
        return dailyModelTokens.first { $0.date == today }
    }

    /// Returns the DailyActivity entries for the last 30 days (inclusive of today),
    /// sorted ascending by date.
    var last30DaysActivity: [DailyActivity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -29, to: today) else {
            return []
        }
        let formatter = Self.dateFormatter()
        return dailyActivity
            .filter { entry in
                guard let date = formatter.date(from: entry.date) else { return false }
                return date >= cutoff
            }
            .sorted { $0.date < $1.date }
    }

    /// Returns the DailyModelTokens entries for the last 30 days (inclusive of today),
    /// sorted ascending by date.
    var last30DaysModelTokens: [DailyModelTokens] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -29, to: today) else {
            return []
        }
        let formatter = Self.dateFormatter()
        return dailyModelTokens
            .filter { entry in
                guard let date = formatter.date(from: entry.date) else { return false }
                return date >= cutoff
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: Private helpers

    private static func todayString() -> String {
        dateFormatter().string(from: Date())
    }

    private static func dateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }
}
