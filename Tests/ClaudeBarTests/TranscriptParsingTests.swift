import Foundation
import XCTest
@testable import ClaudeBarLib

final class TranscriptParsingTests: XCTestCase {
    private let calendar = Calendar.current

    private func makeProjectsRoot() throws -> (root: URL, projects: URL, project: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        let project = projects.appendingPathComponent("-tmp-anonymous-project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, projects, project)
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func assistantLine(
        id: String?,
        date: Date,
        sessionID: String,
        cwd: String = "/tmp/anonymous-project",
        toolUse: Bool = false
    ) throws -> String {
        var message: [String: Any] = [
            "model": "claude-opus-5",
            "usage": [
                "input_tokens": 100,
                "output_tokens": 10,
                "cache_read_input_tokens": 20,
                "cache_creation_input_tokens": 30
            ],
            "content": toolUse ? [["type": "tool_use", "name": "SyntheticTool"]] : []
        ]
        if let id { message["id"] = id }
        let object: [String: Any] = [
            "type": "assistant",
            "timestamp": timestamp(date),
            "sessionId": sessionID,
            "cwd": cwd,
            "message": message
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func writeJSONL(_ lines: [String], to url: URL, mtime: Date? = nil) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: url)
        if let mtime {
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        }
    }

    func testProjectScanDeduplicatesUsageAndScansDespiteSessionIndex() throws {
        let fixture = try makeProjectsRoot()
        let today = calendar.startOfDay(for: Date()).addingTimeInterval(3_600)
        let chunk = try assistantLine(id: "msg-streamed", date: today, sessionID: "session-main")
        let anonymous = try assistantLine(id: nil, date: today, sessionID: "session-main")
        try writeJSONL([chunk, chunk, chunk, anonymous], to: fixture.project.appendingPathComponent("session-main.jsonl"))

        let subagent = try assistantLine(id: "msg-subagent", date: today, sessionID: "agent-1")
        try writeJSONL(
            [subagent],
            to: fixture.project.appendingPathComponent("session-main/subagents/agent-1.jsonl")
        )

        let index: [String: Any] = ["version": 1, "entries": [], "originalPath": fixture.project.path]
        try JSONSerialization.data(withJSONObject: index)
            .write(to: fixture.project.appendingPathComponent("sessions-index.json"))

        let projects = ProjectService.scanAllProjects(dirs: [fixture.projects.path])
        let project = try XCTUnwrap(projects.first)
        let oneMessageCost = CostCalculator.cost(
            modelId: "claude-opus-5", input: 100, output: 10,
            cacheRead: 20, cacheCreation: 30
        )
        XCTAssertEqual(project.totalMessages, 3)
        XCTAssertEqual(project.sessionCount, 2)
        XCTAssertEqual(project.dailyMessageCounts.reduce(0, +), 3)
        XCTAssertEqual(project.estimatedCost, oneMessageCost * 3, accuracy: 0.000_000_1)
    }

    func testYearlyScanDeduplicates365DayMapsAndIncludesSubagents() throws {
        let fixture = try makeProjectsRoot()
        let today = calendar.startOfDay(for: Date()).addingTimeInterval(7_200)
        let chunk = try assistantLine(id: "msg-streamed", date: today, sessionID: "session-main")
        try writeJSONL([chunk, chunk, chunk], to: fixture.project.appendingPathComponent("session-main.jsonl"))
        let subagent = try assistantLine(id: "msg-subagent", date: today, sessionID: "agent-1")
        try writeJSONL(
            [subagent],
            to: fixture.project.appendingPathComponent("session-main/subagents/agent-1.jsonl")
        )

        let result = YearlyHistoryService.scan(projectsDirs: [fixture.projects.path])
        let day = calendar.startOfDay(for: today)
        let stats = try XCTUnwrap(result.dayStats[day])
        let oneMessageCost = CostCalculator.cost(
            modelId: "claude-opus-5", input: 100, output: 10,
            cacheRead: 20, cacheCreation: 30
        )
        XCTAssertEqual(stats.tokens, 320)
        XCTAssertEqual(stats.cost, oneMessageCost * 2, accuracy: 0.000_000_1)
        XCTAssertEqual(result.activity.last?.messageCount, 2)
    }

    func testLiveScanFiltersOldLinesParsesFractionalTimestampsAndDeduplicates() throws {
        let fixture = try makeProjectsRoot()
        let startOfDay = calendar.startOfDay(for: Date())
        let firstToday = startOfDay.addingTimeInterval(3_600.125)
        let streamed = try assistantLine(
            id: "msg-streamed", date: firstToday, sessionID: "session-main", toolUse: true
        )
        let yesterday = try assistantLine(
            id: "msg-yesterday", date: startOfDay.addingTimeInterval(-3_600), sessionID: "session-main"
        )
        let mainURL = fixture.project.appendingPathComponent("session-main.jsonl")
        try writeJSONL([yesterday, streamed, streamed, streamed], to: mainURL, mtime: Date())

        let subagentDate = firstToday.addingTimeInterval(60)
        let subagent = try assistantLine(id: "msg-subagent", date: subagentDate, sessionID: "agent-1")
        try writeJSONL(
            [subagent],
            to: fixture.project.appendingPathComponent("session-main/subagents/agent-1.jsonl"),
            mtime: Date()
        )

        let snapshot = LiveStatsService.scanToday(
            projectsDirectories: [fixture.projects.path],
            startOfDay: startOfDay
        )
        let oneMessageCost = CostCalculator.cost(
            modelId: "claude-opus-5", input: 100, output: 10,
            cacheRead: 20, cacheCreation: 30
        )
        XCTAssertEqual(snapshot.messages, 2)
        XCTAssertEqual(snapshot.tokens, 220)
        XCTAssertEqual(snapshot.toolCalls, 1)
        XCTAssertEqual(snapshot.cost, oneMessageCost * 2, accuracy: 0.000_000_1)
        let parsedFirstActivity = try XCTUnwrap(snapshot.firstActivity)
        XCTAssertEqual(parsedFirstActivity.timeIntervalSince1970, firstToday.timeIntervalSince1970, accuracy: 0.001)
    }

    func testLocatorDiscoversAllProfilesAndNestedSubagentLayout() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        let defaultProjects = home.appendingPathComponent(".claude/projects", isDirectory: true)
        let workProjects = home.appendingPathComponent(".claude-work/projects", isDirectory: true)
        try FileManager.default.createDirectory(at: defaultProjects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workProjects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claudeignored/projects"),
            withIntermediateDirectories: true
        )

        XCTAssertEqual(
            JSONLLocator.allProjectsDirectories(homeDirectory: home.path),
            [defaultProjects.path, workProjects.path].sorted()
        )

        let project = workProjects.appendingPathComponent("encoded-project", isDirectory: true)
        let direct = project.appendingPathComponent("session.jsonl")
        let subagent = project.appendingPathComponent("session/subagents/agent.jsonl")
        try writeJSONL(["{}"], to: direct)
        try writeJSONL(["{}"], to: subagent)
        XCTAssertEqual(
            JSONLLocator.files(inProjectDirectory: project.path),
            [direct.path, subagent.path].sorted()
        )
    }
}
