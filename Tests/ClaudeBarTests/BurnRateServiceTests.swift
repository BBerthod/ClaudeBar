import XCTest
@testable import ClaudeBarLib

// MARK: - BurnRateServiceTests

@MainActor
final class BurnRateServiceTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a temporary directory with a valid `stats-cache.json` and returns
    /// a configured `StatsService` pointing at it.
    ///
    /// - Parameters:
    ///   - todayTokens: Token count attributed to today in the cache.
    ///   - historicalTokens: Per-day token count for each historical day (tokens
    ///     are placed under the model key `"claude-sonnet-4-5"`).
    ///   - historicalDaysCount: Number of historical days to generate, each with
    ///     `historicalTokens`. Dates are relative to today (yesterday, day before, …).
    /// - Returns: A tuple of the temp directory URL and the loaded `StatsService`.
    private func makeTempStatsDir(
        todayTokens: Int,
        historicalTokens: Int = 0,
        historicalDaysCount: Int = 0
    ) throws -> (URL, StatsService) {
        let tempDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayString = DateFormatter.isoDate.string(from: today)

        // Build dailyModelTokens array
        var dailyModelTokens: [[String: Any]] = []

        // Today's entry
        if todayTokens > 0 {
            dailyModelTokens.append([
                "date": todayString,
                "tokensByModel": ["claude-sonnet-4-5": todayTokens]
            ])
        } else {
            // Always include today's entry so todayModelTokens is non-nil
            dailyModelTokens.append([
                "date": todayString,
                "tokensByModel": ["claude-sonnet-4-5": 0]
            ])
        }

        // Historical entries
        for offset in 1 ... max(historicalDaysCount, 1) where offset <= historicalDaysCount {
            guard let pastDate = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dateString = DateFormatter.isoDate.string(from: pastDate)
            dailyModelTokens.append([
                "date": dateString,
                "tokensByModel": ["claude-sonnet-4-5": historicalTokens]
            ])
        }

        // Build dailyActivity array (mirrors dailyModelTokens dates)
        var dailyActivity: [[String: Any]] = []
        for entry in dailyModelTokens {
            guard let date = entry["date"] as? String else { continue }
            dailyActivity.append([
                "date": date,
                "messageCount": 1,
                "sessionCount": 1,
                "toolCallCount": 0
            ])
        }

        let json: [String: Any] = [
            "version": 1,
            "lastComputedDate": todayString,
            "dailyActivity": dailyActivity,
            "dailyModelTokens": dailyModelTokens,
            "modelUsage": [String: Any](),
            "totalSessions": dailyActivity.count,
            "totalMessages": dailyActivity.count,
            "hourCounts": [String: Int]()
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let cacheURL = tempDir.appendingPathComponent("stats-cache.json")
        try data.write(to: cacheURL)

        let service = StatsService(claudeDir: tempDir.path)
        return (tempDir, service)
    }

    // MARK: - Tests

    /// StatsService without a file → burnRate must be nil.
    func testNilBurnRateWhenNoStats() {
        let emptyDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        // Directory does not exist — no stats-cache.json
        let statsService = StatsService(claudeDir: emptyDir.path)
        XCTAssertNil(statsService.stats, "stats should be nil when no stats-cache.json exists")

        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)

        XCTAssertNil(burnRateService.burnRate, "burnRate must be nil when StatsService has no stats")
    }

    /// today=50 tokens, historical average=100_000/day → zone must be .chill.
    ///
    /// Ratio reasoning: projectedDailyTokens is at most todayTokens * (10h / 1h) = 500
    /// in the extreme case. 500 / 100_000 = 0.005 — well below the 0.7 threshold.
    func testZoneChill() throws {
        let (_, statsService) = try makeTempStatsDir(
            todayTokens: 50,
            historicalTokens: 100_000,
            historicalDaysCount: 5
        )

        XCTAssertNotNil(statsService.stats, "stats must be loaded for this test to be meaningful")

        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)

        let burnRate = try XCTUnwrap(burnRateService.burnRate, "burnRate must not be nil")
        XCTAssertEqual(
            burnRate.zone, .chill,
            "Expected .chill with today=50 vs avg=100_000 (ratio ≈ 0.005)"
        )
    }

    /// today=500_000 tokens, historical average=1_000/day → zone must be .critical.
    ///
    /// Ratio reasoning: projectedDailyTokens is at least todayTokens = 500_000
    /// (remainingHours can be 0 at end of workday). 500_000 / 1_000 = 500 — far above 2.0.
    func testZoneCritical() throws {
        let (_, statsService) = try makeTempStatsDir(
            todayTokens: 500_000,
            historicalTokens: 1_000,
            historicalDaysCount: 5
        )

        XCTAssertNotNil(statsService.stats, "stats must be loaded for this test to be meaningful")

        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)

        let burnRate = try XCTUnwrap(burnRateService.burnRate, "burnRate must not be nil")
        XCTAssertEqual(
            burnRate.zone, .critical,
            "Expected .critical with today=500_000 vs avg=1_000 (ratio=500)"
        )
    }

    /// averageDailyTokens must be computed from historical days only (today excluded).
    ///
    /// Setup: today=99_999, 5 historical days at 2_000 each.
    /// Expected averageDailyTokens = 2_000 (not influenced by today's 99_999).
    func testAverageDailyTokensExcludesToday() throws {
        let (_, statsService) = try makeTempStatsDir(
            todayTokens: 99_999,
            historicalTokens: 2_000,
            historicalDaysCount: 5
        )

        XCTAssertNotNil(statsService.stats, "stats must be loaded for this test to be meaningful")

        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)

        let burnRate = try XCTUnwrap(burnRateService.burnRate, "burnRate must not be nil")
        XCTAssertEqual(
            burnRate.averageDailyTokens, 2_000,
            "averageDailyTokens must exclude today; 5 days × 2_000 tokens = avg 2_000"
        )
    }

    /// When there is no historical data, averageDailyTokens falls back to today's tokens.
    ///
    /// BurnRateService's fallback (no previousTokenDays): avgTokens = Double(todayTokens).
    func testAverageDailyTokensWithNoHistory() throws {
        let (_, statsService) = try makeTempStatsDir(
            todayTokens: 1_234,
            historicalTokens: 0,
            historicalDaysCount: 0
        )

        XCTAssertNotNil(statsService.stats, "stats must be loaded for this test to be meaningful")

        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)

        let burnRate = try XCTUnwrap(burnRateService.burnRate, "burnRate must not be nil")
        XCTAssertEqual(
            burnRate.averageDailyTokens, 1_234,
            "With no historical days, averageDailyTokens must fall back to today's token count"
        )
    }
}
