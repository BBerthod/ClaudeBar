import Foundation
import XCTest
@testable import ClaudeBarLib

final class YearlyHistoryCacheTests: XCTestCase {
    private let calendar = Calendar.current

    private typealias ScanResult = (
        dayStats: [Date: DayStats], activity: [DailyActivity], tokens: [DailyModelTokens],
        modelBreakdown: [String: ModelTokenBreakdown], models: Set<String>
    )

    /// Comparable copy of every aggregate the service publishes (costs compared bit for bit).
    private struct Snapshot: Equatable {
        let dayStats: [Date: String]
        let activity: [String]
        let tokens: [String]
        let breakdown: [String: [Int]]
        let models: Set<String>

        init(_ result: ScanResult) {
            dayStats = result.dayStats.mapValues { "\($0.tokens)|\($0.cost.bitPattern)" }
            activity = result.activity.map { "\($0.date)|\($0.messageCount)|\($0.sessionCount)|\($0.toolCallCount)" }
            tokens = result.tokens.map { day in
                day.date + "|" + day.tokensByModel.sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            }
            breakdown = result.modelBreakdown.mapValues { [$0.input, $0.output, $0.cacheRead, $0.cacheCreation] }
            models = result.models
        }
    }

    private func makeProject() throws -> (projects: URL, project: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        let project = projects.appendingPathComponent("-tmp-anonymous-project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (projects, project)
    }

    private func line(
        id: String?, daysAgo: Int, session: String, model: String = "claude-opus-5",
        input: Int = 100, output: Int = 10, toolUse: Bool = false
    ) throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
            .addingTimeInterval(3_600)
        var message: [String: Any] = [
            "model": model,
            "usage": [
                "input_tokens": input,
                "output_tokens": output,
                "cache_read_input_tokens": 20,
                "cache_creation_input_tokens": 30
            ],
            "content": toolUse ? [["type": "tool_use", "name": "SyntheticTool"]] : []
        ]
        if let id { message["id"] = id }
        let object: [String: Any] = [
            "type": "assistant",
            "timestamp": formatter.string(from: date),
            "sessionId": session,
            "message": message
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func write(_ lines: [String], to url: URL, mtime: Date? = nil) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: url)
        if let mtime {
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        }
    }

    private func fullScan(_ projects: URL) -> Snapshot {
        Snapshot(YearlyHistoryService.scanWithModels(projectsDirs: [projects.path]))
    }

    /// Three transcripts covering the 30-day and the 365-day windows, a subagent and an anonymous line.
    private func writeFixture(_ project: URL) throws -> (first: URL, second: URL, subagent: URL) {
        let first = project.appendingPathComponent("session-a.jsonl")
        try write([
            try line(id: "msg-1", daysAgo: 0, session: "session-a", toolUse: true),
            try line(id: "msg-1", daysAgo: 0, session: "session-a", toolUse: true),
            try line(id: nil, daysAgo: 2, session: "session-a"),
            try line(id: "msg-old", daysAgo: 100, session: "session-a")
        ], to: first)
        let second = project.appendingPathComponent("session-b.jsonl")
        try write([
            try line(id: "msg-2", daysAgo: 1, session: "session-b", model: "claude-sonnet-5", input: 7, output: 3)
        ], to: second)
        let subagent = project.appendingPathComponent("session-a/subagents/agent-1.jsonl")
        try write([try line(id: "msg-3", daysAgo: 0, session: "agent-1")], to: subagent)
        return (first, second, subagent)
    }

    func testSecondScanWithoutChangesReadsNoFile() throws {
        let fixture = try makeProject()
        let files = try writeFixture(fixture.project)
        var cache = YearlyHistoryCache()

        let first = Snapshot(YearlyHistoryService.scanWithModels(projectsDirs: [fixture.projects.path], cache: &cache))
        XCTAssertEqual(Set(cache.lastReadPaths), Set([files.first.path, files.second.path, files.subagent.path]))

        let second = Snapshot(YearlyHistoryService.scanWithModels(projectsDirs: [fixture.projects.path], cache: &cache))
        XCTAssertEqual(cache.lastReadPaths, [])
        XCTAssertEqual(second, first)
        XCTAssertEqual(second, fullScan(fixture.projects))
    }

    func testOnlyTheModifiedFileIsReadAgain() throws {
        let fixture = try makeProject()
        let files = try writeFixture(fixture.project)
        var cache = YearlyHistoryCache()
        let before = Snapshot(YearlyHistoryService.scanWithModels(projectsDirs: [fixture.projects.path], cache: &cache))

        // Appended line: the size changes.
        let handle = try FileHandle(forWritingTo: files.second)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((try line(id: "msg-4", daysAgo: 0, session: "session-b") + "\n").utf8))
        try handle.close()

        let appended = Snapshot(YearlyHistoryService.scanWithModels(projectsDirs: [fixture.projects.path], cache: &cache))
        XCTAssertEqual(cache.lastReadPaths, [files.second.path])
        XCTAssertEqual(appended, fullScan(fixture.projects))
        XCTAssertNotEqual(appended, before)

        // Same size, later modification date: the file is read again too.
        let attributes = try FileManager.default.attributesOfItem(atPath: files.first.path)
        let size = try XCTUnwrap(attributes[.size] as? NSNumber).intValue
        let mtime = try XCTUnwrap(attributes[.modificationDate] as? Date)
        try write([
            try line(id: "msg-1", daysAgo: 0, session: "session-a", input: 900, toolUse: true),
            try line(id: "msg-1", daysAgo: 0, session: "session-a", input: 900, toolUse: true),
            try line(id: nil, daysAgo: 2, session: "session-a"),
            try line(id: "msg-old", daysAgo: 100, session: "session-a")
        ], to: files.first, mtime: mtime.addingTimeInterval(10))
        let rewrittenSize = try XCTUnwrap(
            try FileManager.default.attributesOfItem(atPath: files.first.path)[.size] as? NSNumber
        ).intValue
        XCTAssertEqual(rewrittenSize, size)

        let rewritten = Snapshot(YearlyHistoryService.scanWithModels(projectsDirs: [fixture.projects.path], cache: &cache))
        XCTAssertEqual(cache.lastReadPaths, [files.first.path])
        XCTAssertEqual(rewritten, fullScan(fixture.projects))
        XCTAssertNotEqual(rewritten, appended)
    }

    func testDeletedFileContributionIsRemoved() throws {
        let fixture = try makeProject()
        let files = try writeFixture(fixture.project)
        var cache = YearlyHistoryCache()
        _ = YearlyHistoryService.scanWithModels(projectsDirs: [fixture.projects.path], cache: &cache)

        try FileManager.default.removeItem(at: files.second)

        let result = YearlyHistoryService.scanWithModels(projectsDirs: [fixture.projects.path], cache: &cache)
        XCTAssertEqual(cache.lastReadPaths, [])
        XCTAssertEqual(Snapshot(result), fullScan(fixture.projects))
        XCTAssertFalse(result.models.contains("claude-sonnet-5"))
        XCTAssertNil(result.modelBreakdown["claude-sonnet-5"])
    }

    func testDuplicateAcrossFilesCountsTheFirstSortedFileLikeAFullScan() throws {
        let fixture = try makeProject()
        // Same message id on the same day in two transcripts, with different usage:
        // the first file in sorted path order is the one counted.
        let earlier = fixture.project.appendingPathComponent("a-session.jsonl")
        let later = fixture.project.appendingPathComponent("b-session.jsonl")
        try write([try line(id: "msg-dup", daysAgo: 0, session: "a-session", input: 100, output: 10)], to: earlier)
        try write([
            try line(id: "msg-dup", daysAgo: 0, session: "b-session", input: 500, output: 50),
            try line(id: "msg-dup", daysAgo: 1, session: "b-session", input: 1, output: 1)
        ], to: later)
        let today = calendar.startOfDay(for: Date())
        var cache = YearlyHistoryCache()

        let both = YearlyHistoryService.scanWithModels(projectsDirs: [fixture.projects.path], cache: &cache)
        XCTAssertEqual(both.dayStats[today]?.tokens, 100 + 10 + 20 + 30)
        XCTAssertEqual(both.activity.last?.messageCount, 1)
        XCTAssertEqual(both.activity.last?.sessionCount, 1)
        XCTAssertEqual(both.modelBreakdown["claude-opus-5"]?.input, 100 + 1)
        XCTAssertEqual(Snapshot(both), fullScan(fixture.projects))

        // Once the earlier copy disappears, the later file's copy counts, without reading it again.
        try FileManager.default.removeItem(at: earlier)
        let laterOnly = YearlyHistoryService.scanWithModels(projectsDirs: [fixture.projects.path], cache: &cache)
        XCTAssertEqual(cache.lastReadPaths, [])
        XCTAssertEqual(laterOnly.dayStats[today]?.tokens, 500 + 50 + 20 + 30)
        XCTAssertEqual(laterOnly.activity.last?.messageCount, 1)
        XCTAssertEqual(Snapshot(laterOnly), fullScan(fixture.projects))
    }

    func testTranscriptModifiedBeforeTheWindowIsNotOpened() throws {
        let fixture = try makeProject()
        let files = try writeFixture(fixture.project)
        let stale = fixture.project.appendingPathComponent("stale.jsonl")
        let staleDate = calendar.date(byAdding: .day, value: -400, to: Date())!
        try write([try line(id: "msg-stale", daysAgo: 400, session: "stale")], to: stale, mtime: staleDate)
        var cache = YearlyHistoryCache()

        let result = YearlyHistoryService.scanWithModels(projectsDirs: [fixture.projects.path], cache: &cache)
        XCTAssertEqual(Set(cache.lastReadPaths), Set([files.first.path, files.second.path, files.subagent.path]))
        try FileManager.default.removeItem(at: stale)
        XCTAssertEqual(Snapshot(result), fullScan(fixture.projects))
    }
}
