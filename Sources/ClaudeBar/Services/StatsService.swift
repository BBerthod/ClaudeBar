import Foundation

@Observable
@MainActor
final class StatsService {
    private(set) var stats: StatsCache?
    private(set) var lastError: String?
    private var fileWatcher = FileWatcher()

    private let statsPath: String

    init(claudeDir: String = "~/.claude") {
        self.statsPath = NSString(string: claudeDir).expandingTildeInPath + "/stats-cache.json"
        loadStats()
        startWatching()
    }

    // MARK: - Computed Properties

    var todayTokens: Int {
        guard let today = stats?.todayModelTokens else { return 0 }
        return today.tokensByModel.values.reduce(0, +)
    }

    var todayMessages: Int {
        stats?.todayActivity?.messageCount ?? 0
    }

    var todaySessions: Int {
        stats?.todayActivity?.sessionCount ?? 0
    }

    var todayToolCalls: Int {
        stats?.todayActivity?.toolCallCount ?? 0
    }

    var todayCostEstimate: Double {
        guard let stats else { return 0 }
        guard let todayTokens = stats.todayModelTokens else { return 0 }
        return CostCalculator.estimateDailyCost(
            tokens: todayTokens.tokensByModel,
            modelUsage: stats.modelUsage
        )
    }

    var todayCostFormatted: String {
        CostCalculator.formatCost(todayCostEstimate)
    }

    /// Sorted descending by token count.
    var tokensByModelToday: [(model: String, tokens: Int)] {
        guard let today = stats?.todayModelTokens else { return [] }
        return today.tokensByModel
            .map { (model: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }
    }

    var last30DaysActivity: [DailyActivity] {
        stats?.last30DaysActivity ?? []
    }

    var last30DaysTokens: [DailyModelTokens] {
        stats?.last30DaysModelTokens ?? []
    }

    /// Total estimated cost across all recorded days.
    ///
    /// Sums per-day cost estimates rather than applying pricing to raw cumulative
    /// token counters. The cumulative `modelUsage.cacheReadInputTokens` can reach
    /// billions, which inflates the total to absurd levels if priced directly.
    var totalCostEstimate: Double {
        guard let stats else { return 0 }
        return stats.dailyModelTokens.reduce(0.0) { sum, day in
            sum + CostCalculator.estimateDailyCost(
                tokens: day.tokensByModel,
                modelUsage: stats.modelUsage
            )
        }
    }

    // MARK: - Display Name

    /// Converts a raw model ID to a short human-readable name.
    /// Examples:
    ///   "claude-opus-4-6"              → "Opus 4.6"
    ///   "claude-sonnet-4-5-20250929"   → "Sonnet 4.5"
    ///   "claude-haiku-4-5-20251001"    → "Haiku 4.5"
    ///   "claude-opus-4-5-20251101"     → "Opus 4.5"
    static func displayName(for modelId: String) -> String {
        // Strip a trailing date suffix like -20250929 or -20251001 (8 digits after a dash)
        let dateSuffixPattern = #"-\d{8}$"#
        var cleaned = modelId
        if let range = cleaned.range(of: dateSuffixPattern, options: .regularExpression) {
            cleaned = String(cleaned[..<range.lowerBound])
        }

        // Identify the model family
        let lower = cleaned.lowercased()
        let family: String
        if lower.contains("opus") {
            family = "Opus"
        } else if lower.contains("sonnet") {
            family = "Sonnet"
        } else if lower.contains("haiku") {
            family = "Haiku"
        } else {
            // Unknown model — return a sanitised version of the raw ID
            return modelId
        }

        // Extract the version number: the last numeric segment(s) after "claude-<family>-"
        // e.g. "claude-opus-4-6" → ["4", "6"], "claude-sonnet-4-5" → ["4", "5"]
        let parts = cleaned.components(separatedBy: "-")
        // Drop "claude" and the family name parts; collect trailing numeric tokens
        var versionParts: [String] = []
        var pastFamily = false
        for part in parts {
            if !pastFamily {
                if part.lowercased() == family.lowercased() {
                    pastFamily = true
                }
                continue
            }
            // Accept only pure-digit segments as version components
            if part.allSatisfy({ $0.isNumber }) {
                versionParts.append(part)
            }
        }

        if versionParts.isEmpty {
            return family
        }

        // Format: major.minor (join with ".")
        let version = versionParts.joined(separator: ".")
        return "\(family) \(version)"
    }

    // MARK: - Private

    private func loadStats() {
        let url = URL(fileURLWithPath: statsPath)
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            stats = try decoder.decode(StatsCache.self, from: data)
            lastError = nil
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // File doesn't exist yet — not an error, just no data
            stats = nil
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startWatching() {
        fileWatcher.watch(path: statsPath) { [weak self] in
            self?.loadStats()
        }
    }
}
