import XCTest
@testable import ClaudeBarLib

// MARK: - ExportServiceTests

@MainActor
final class ExportServiceTests: XCTestCase {

    // MARK: - Helper

    /// Builds a minimal `StatsCache` with the given dates and per-day values.
    ///
    /// - Parameters:
    ///   - dates: ISO-8601 date strings ("YYYY-MM-DD") to populate.
    ///   - tokensPerDay: Token count credited to the model "claude-sonnet-4-6" for every date.
    ///   - messagesPerDay: Message count for every date (also used as session count).
    private func makeStats(
        dates: [String],
        tokensPerDay: Int = 100,
        messagesPerDay: Int = 5
    ) -> StatsCache {
        let activity = dates.map { date in
            DailyActivity(
                date: date,
                messageCount: messagesPerDay,
                sessionCount: max(1, messagesPerDay / 5),
                toolCallCount: messagesPerDay * 2
            )
        }
        let tokens = dates.map { date in
            DailyModelTokens(date: date, tokensByModel: ["claude-sonnet-4-6": tokensPerDay])
        }

        return StatsCache(
            version: 1,
            lastComputedDate: dates.last ?? "2026-01-01",
            dailyActivity: activity,
            dailyModelTokens: tokens,
            modelUsage: [:],
            totalSessions: dates.count * max(1, messagesPerDay / 5),
            totalMessages: dates.count * messagesPerDay,
            longestSession: nil,
            firstSessionDate: dates.first,
            hourCounts: [:],
            totalSpeculationTimeSavedMs: nil
        )
    }

    // MARK: - CSV Tests

    func testCSVHeaderRow() {
        // Arrange
        let stats = makeStats(dates: ["2026-01-01"])

        // Act
        let csv = ExportService.buildCSV(stats: stats, modelUsage: stats.modelUsage)
        let firstLine = csv.components(separatedBy: "\n").first ?? ""

        // Assert
        XCTAssertEqual(firstLine, "date,sessions,messages,tool_calls,tokens,cost_usd")
    }

    func testCSVOneRowPerDate() {
        // Arrange
        let dates = ["2026-01-01", "2026-01-02", "2026-01-03"]
        let stats = makeStats(dates: dates)

        // Act
        let csv = ExportService.buildCSV(stats: stats, modelUsage: stats.modelUsage)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Assert: 1 header + 3 data rows
        XCTAssertEqual(lines.count, 4)
    }

    func testCSVColumnsFormat() {
        // Arrange
        let stats = makeStats(dates: ["2026-03-15"], tokensPerDay: 1_000, messagesPerDay: 10)

        // Act
        let csv = ExportService.buildCSV(stats: stats, modelUsage: stats.modelUsage)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Assert: data row (index 1) has 6 comma-separated columns with expected values
        XCTAssertEqual(lines.count, 2)
        let columns = lines[1].components(separatedBy: ",")
        XCTAssertEqual(columns.count, 6)
        XCTAssertEqual(columns[0], "2026-03-15")              // date
        XCTAssertEqual(columns[1], "2")                       // sessionCount = 10/5 = 2
        XCTAssertEqual(columns[2], "10")                      // messageCount
        XCTAssertEqual(columns[3], "20")                      // toolCallCount = 10*2
        XCTAssertEqual(columns[4], "1000")                    // totalTokens
        // cost_usd: no modelUsage entry → input-only fallback (sonnet: $3/MTok)
        // = 1000 / 1_000_000 * 3.0 = 0.003 → "0.0030"
        XCTAssertEqual(columns[5], "0.0030")
    }

    func testCSVEmptyStats() {
        // Arrange
        let stats = makeStats(dates: [])

        // Act
        let csv = ExportService.buildCSV(stats: stats, modelUsage: stats.modelUsage)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Assert: only the header row, no data rows
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0], "date,sessions,messages,tool_calls,tokens,cost_usd")
    }

    // MARK: - JSON Tests

    func testJSONValidOutput() {
        // Arrange
        let stats = makeStats(dates: ["2026-01-01"])

        // Act
        let json = ExportService.buildJSON(stats: stats, modelUsage: stats.modelUsage)
        let data = json.data(using: .utf8)

        // Assert: parsable without error
        XCTAssertNotNil(data)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data!, options: []))
    }

    func testJSONRootKeys() {
        // Arrange
        let stats = makeStats(dates: ["2026-01-01"])

        // Act
        let json = ExportService.buildJSON(stats: stats, modelUsage: stats.modelUsage)
        let data = json.data(using: .utf8)!
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Assert: all five expected root keys are present
        XCTAssertNotNil(root)
        XCTAssertNotNil(root?["exported_at"])
        XCTAssertNotNil(root?["total_cost_usd"])
        XCTAssertNotNil(root?["total_sessions"])
        XCTAssertNotNil(root?["total_messages"])
        XCTAssertNotNil(root?["daily_data"])
    }

    func testJSONDailyDataStructure() {
        // Arrange
        let stats = makeStats(dates: ["2026-04-20"], tokensPerDay: 500, messagesPerDay: 5)

        // Act
        let json = ExportService.buildJSON(stats: stats, modelUsage: stats.modelUsage)
        let data = json.data(using: .utf8)!
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let daily = root?["daily_data"] as? [[String: Any]]
        let entry = daily?.first

        // Assert: entry keys and values match the makeStats inputs
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?["date"] as? String, "2026-04-20")
        XCTAssertEqual(entry?["sessions"] as? Int, 1)         // max(1, 5/5) = 1
        XCTAssertEqual(entry?["messages"] as? Int, 5)
        XCTAssertEqual(entry?["tool_calls"] as? Int, 10)      // 5 * 2
        XCTAssertEqual(entry?["tokens"] as? Int, 500)
        // cost_usd: 500 / 1_000_000 * 3.0 = 0.0015 → rounded to 4 decimal places = 0.0015
        let cost = entry?["cost_usd"] as? Double
        XCTAssertNotNil(cost)
        XCTAssertEqual(cost!, 0.0015, accuracy: 1e-9)
    }
}
