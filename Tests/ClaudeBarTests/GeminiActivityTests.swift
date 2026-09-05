import XCTest
@testable import ClaudeBarLib

final class GeminiActivityTests: XCTestCase {
    private let startOfDay = ISO8601DateFormatter().date(from: "2026-09-05T00:00:00+02:00")!

    func testParsesSummaryRows() {
        let rows = [
            "c1\t2026-09-05 10:00:00.5+02:00\t2026-09-05 10:05:00+02:00\t1\t0\tcoder\t[\"file:///Users/me/Dev/app\"]",
            "c2\t2026-09-04 23:59:59+02:00\t2026-09-05 00:10:00+02:00\t0\t0\t\t[\"file:///Users/me/Dev/old\"]",   // yesterday
            "c3\t2026-09-05T08:00:00Z\t2026-09-05T08:01:00Z\t1\t1\treviewer\t/Users/me/Dev/app",                    // killed → not active
            "c4\t2026-09-05 12:00:00+02:00\t2026-09-05 12:00:00+02:00\t0\t0\tcoder\t[]",
        ]
        let a = GeminiActivityParser.parseSummaries(tsvRows: rows, startOfDay: startOfDay)
        XCTAssertEqual(a.conversationsToday, 3)          // c1, c3, c4
        XCTAssertEqual(a.activeConversations, 1)         // c1 only (c3 killed)
        XCTAssertEqual(a.agentsToday, ["coder", "reviewer"])
        XCTAssertEqual(a.workspacesToday, ["app"])       // last path component, deduplicated, sorted
    }

    func testParsesHistoryLines() {
        let lines = [
            #"{"display":"hi","timestamp":1788602400000,"workspace":"/Users/me/Dev/app","conversationId":"c1"}"#,   // 2026-09-05 12:00 +02:00
            #"{"display":"old","timestamp":1788516000000,"workspace":"/Users/me/Dev/app"}"#,                        // yesterday
            #"not json"#,
            #"{"display":"again","timestamp":1788606000000,"workspace":"/Users/me/Dev/app","conversationId":"c1"}"#,
        ]
        let h = GeminiActivityParser.parseHistory(lines: lines, startOfDay: startOfDay)
        XCTAssertEqual(h.promptsToday, 2)
        XCTAssertEqual(h.lastPromptAt, Date(timeIntervalSince1970: 1_788_606_000))
    }
    func testDateFormatsAndInvalidInput() {
        let expected = ISO8601DateFormatter().date(from: "2026-09-05T10:00:00Z")!
        for value in ["2026-09-05T10:00:00Z", "2026-09-05 12:00:00+02:00", "2026-09-05 12:00:00.000000+02:00", "2026-09-05T10:00:00.000Z"] {
            XCTAssertEqual(GeminiActivityParser.parseDate(value), expected, value)
        }
        XCTAssertNil(GeminiActivityParser.parseDate("invalid"))
    }

    func testMalformedRowsAndDayBoundary() {
        let a = GeminiActivityParser.parseSummaries(tsvRows: ["invalid", "c1\t2026-09-05T00:00:00+02:00\t\t0\t0\t\t[]", "c2\tinvalid\t2026-09-05T10:00:00Z\t1\t0\tignored\t/tmp/ignored"], startOfDay: startOfDay)
        XCTAssertEqual(a.conversationsToday, 1)
        XCTAssertEqual(a.activeConversations, 1)
        XCTAssertTrue(a.agentsToday.isEmpty)
        XCTAssertTrue(a.workspacesToday.isEmpty)
        let h = GeminiActivityParser.parseHistory(lines: ["{}", "{\"timestamp\":true}", "{\"timestamp\":\"bad\"}", "{\"timestamp\":\(startOfDay.timeIntervalSince1970 * 1000)}"], startOfDay: startOfDay)
        XCTAssertEqual(h.promptsToday, 1)
        XCTAssertEqual(h.lastPromptAt, startOfDay)
    }

    func testLastPromptIncludesYesterday() {
        let yesterday = startOfDay.addingTimeInterval(-1)
        let h = GeminiActivityParser.parseHistory(lines: ["{\"timestamp\":\(yesterday.timeIntervalSince1970 * 1000)}"], startOfDay: startOfDay)
        XCTAssertEqual(h.promptsToday, 0)
        XCTAssertEqual(h.lastPromptAt, yesterday)
    }
}
