import XCTest
@testable import ClaudeBarLib

// MARK: - AnomalyServiceTests

@MainActor
final class AnomalyServiceTests: XCTestCase {

    // MARK: - Constants

    private let defaultsKey = "claudebar.lastAnomalyDate"

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Builds a temporary directory with a valid `stats-cache.json` and returns
    /// a configured `StatsService` pointing at it.
    ///
    /// - Parameters:
    ///   - todayTokens: Token count attributed to today in the cache.
    ///   - historicalTokens: Per-day token count for each historical day.
    ///   - historicalDaysCount: Number of historical days to generate.
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

        dailyModelTokens.append([
            "date": todayString,
            "tokensByModel": ["claude-sonnet-4-5": todayTokens]
        ])

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

    /// Creates a `BurnRateService` whose `burnRate.percentOfAverage >= 2.0`.
    ///
    /// Ratio: today=500_000 tokens, historical avg=1_000/day → projected ratio ≈ 500.
    private func makeHighRatioBurnRateService() throws -> BurnRateService {
        let (_, statsService) = try makeTempStatsDir(
            todayTokens: 500_000,
            historicalTokens: 1_000,
            historicalDaysCount: 5
        )
        let service = BurnRateService()
        service.update(statsService: statsService)
        return service
    }

    /// Creates a `BurnRateService` whose `burnRate.percentOfAverage < 2.0`.
    ///
    /// Ratio: today=50 tokens, historical avg=100_000/day → projected ratio ≈ 0.005.
    private func makeLowRatioBurnRateService() throws -> BurnRateService {
        let (_, statsService) = try makeTempStatsDir(
            todayTokens: 50,
            historicalTokens: 100_000,
            historicalDaysCount: 5
        )
        let service = BurnRateService()
        service.update(statsService: statsService)
        return service
    }

    // MARK: - Tests

    /// `BurnRateService` without a stats update → `burnRate` is nil → `lastAnomalyDate` must remain nil.
    func testNoFireWhenBurnRateIsNil() {
        let anomalyService = AnomalyService()
        let burnRateService = BurnRateService()
        let notificationService = NotificationService()

        XCTAssertNil(burnRateService.burnRate, "Precondition: burnRate must be nil before update")

        anomalyService.check(burnRateService: burnRateService, notificationService: notificationService)

        XCTAssertNil(anomalyService.lastAnomalyDate, "lastAnomalyDate must remain nil when burnRate is nil")
        XCTAssertNil(
            UserDefaults.standard.string(forKey: defaultsKey),
            "UserDefaults must not be written when burnRate is nil"
        )
    }

    /// `burnRate.percentOfAverage < 2.0` → `lastAnomalyDate` must remain nil.
    func testNoFireWhenRatioBelowThreshold() throws {
        let anomalyService = AnomalyService()
        let burnRateService = try makeLowRatioBurnRateService()
        let notificationService = NotificationService()

        let burnRate = try XCTUnwrap(burnRateService.burnRate, "Precondition: burnRate must not be nil")
        XCTAssertLessThan(
            burnRate.percentOfAverage, 2.0,
            "Precondition: percentOfAverage must be below threshold"
        )

        anomalyService.check(burnRateService: burnRateService, notificationService: notificationService)

        XCTAssertNil(anomalyService.lastAnomalyDate, "lastAnomalyDate must remain nil when ratio < 2.0")
        XCTAssertNil(
            UserDefaults.standard.string(forKey: defaultsKey),
            "UserDefaults must not be written when ratio < 2.0"
        )
    }

    /// `burnRate.percentOfAverage >= 2.0`, first fire of the day → `lastAnomalyDate` must equal today.
    func testFiresWhenRatioAboveThreshold() throws {
        let anomalyService = AnomalyService()
        let burnRateService = try makeHighRatioBurnRateService()
        let notificationService = NotificationService()

        let burnRate = try XCTUnwrap(burnRateService.burnRate, "Precondition: burnRate must not be nil")
        XCTAssertGreaterThanOrEqual(
            burnRate.percentOfAverage, 2.0,
            "Precondition: percentOfAverage must be at or above threshold"
        )

        anomalyService.check(burnRateService: burnRateService, notificationService: notificationService)

        let today = DateFormatter.isoDate.string(from: Date())
        XCTAssertEqual(anomalyService.lastAnomalyDate, today, "lastAnomalyDate must equal today after first fire")
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: defaultsKey), today,
            "UserDefaults must persist today's date after first fire"
        )
    }

    /// Already fired today → second call must not update `lastAnomalyDate` (dedup guard).
    func testNoSecondFireSameDay() throws {
        let today = DateFormatter.isoDate.string(from: Date())

        // Pre-seed UserDefaults so AnomalyService.init() loads today's date
        UserDefaults.standard.set(today, forKey: defaultsKey)

        let anomalyService = AnomalyService()
        XCTAssertEqual(anomalyService.lastAnomalyDate, today, "Precondition: lastAnomalyDate must equal today")

        let burnRateService = try makeHighRatioBurnRateService()
        let notificationService = NotificationService()

        // Record the time before calling check so we can verify nothing changed
        let dateBeforeCheck = anomalyService.lastAnomalyDate

        anomalyService.check(burnRateService: burnRateService, notificationService: notificationService)

        XCTAssertEqual(
            anomalyService.lastAnomalyDate, dateBeforeCheck,
            "lastAnomalyDate must not change on second fire the same day"
        )
    }

    /// Fired yesterday → today's call must trigger again and update `lastAnomalyDate` to today.
    func testFiresAgainNextDay() throws {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else {
            XCTFail("Could not compute yesterday's date")
            return
        }
        let yesterdayString = DateFormatter.isoDate.string(from: yesterday)
        let today = DateFormatter.isoDate.string(from: Date())

        // Pre-seed UserDefaults with yesterday's date so AnomalyService.init() loads it
        UserDefaults.standard.set(yesterdayString, forKey: defaultsKey)

        let anomalyService = AnomalyService()
        XCTAssertEqual(
            anomalyService.lastAnomalyDate, yesterdayString,
            "Precondition: lastAnomalyDate must equal yesterday"
        )

        let burnRateService = try makeHighRatioBurnRateService()
        let notificationService = NotificationService()

        anomalyService.check(burnRateService: burnRateService, notificationService: notificationService)

        XCTAssertEqual(
            anomalyService.lastAnomalyDate, today,
            "lastAnomalyDate must update to today when last fire was yesterday"
        )
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: defaultsKey), today,
            "UserDefaults must persist today's date when re-firing after a day"
        )
    }
}
