import XCTest
@testable import ClaudeBarLib

final class GeminiActivityServiceTests: XCTestCase {
    private var directory: URL!
    private let now = ISO8601DateFormatter().date(from: "2026-09-05T12:00:00Z")!
    private var database: URL { directory.appendingPathComponent("conversation_summaries.db") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("gemini #? \(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, """
        CREATE TABLE conversation_summaries (
          conversation_id TEXT PRIMARY KEY, title TEXT, preview TEXT, step_count INTEGER,
          last_modified_time TEXT, workspace_uris TEXT, status TEXT, source TEXT,
          project_id TEXT, agent_name TEXT, parent_conversation_id TEXT, nesting_depth INTEGER,
          not_fully_idle INTEGER, killed INTEGER, last_user_input_time TEXT
        );
        INSERT INTO conversation_summaries
          (conversation_id, last_user_input_time, last_modified_time, not_fully_idle, killed, agent_name, workspace_uris)
        VALUES
          ('c1', '2026-09-05 10:00:00.5+02:00', '2026-09-05 10:05:00+02:00', 1, 0, 'coder', '["file:///Users/me/Dev/app"]'),
          ('c2', '2026-09-04 10:00:00+02:00', '2026-09-05 00:10:00+02:00', 0, 0, '', '["file:///Users/me/Dev/old"]'),
          ('c3', '2026-09-05T08:00:00Z', '2026-09-05T08:01:00Z', 1, 1, 'reviewer', '/Users/me/Dev/app'),
          ('c4', '2026-09-05 12:00:00+02:00', '2026-09-05 12:00:00+02:00', 0, 0, 'coder', '[]');
        """]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        try """
        {"timestamp":1788602400000}
        {"timestamp":1788516000000}
        not json
        {"timestamp":1788606000000}
        """.write(to: directory.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)
        try Data("token-presence-only".utf8).write(to: directory.appendingPathComponent("antigravity-oauth-token"))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    @MainActor private func service() -> GeminiActivityService {
        let fixedNow = now
        return GeminiActivityService(cliDirectory: directory, now: { fixedNow }, disablePolling: true)
    }

    @MainActor func testNotInstalledWithoutDirectory() async {
        let service = GeminiActivityService(cliDirectory: directory.appendingPathComponent("missing"), disablePolling: true)
        await service.refresh()
        XCTAssertFalse(service.isInstalled)
        XCTAssertEqual(service.activity, GeminiActivity())
        XCTAssertNil(service.lastError)
    }

    @MainActor func testRefreshReadsAllThreeSources() async {
        let service = service()
        await service.refresh()
        XCTAssertTrue(service.isInstalled)
        XCTAssertEqual(service.activity.conversationsToday, 3)
        XCTAssertEqual(service.activity.promptsToday, 2)
        XCTAssertEqual(service.activity.activeConversations, 1)
        XCTAssertEqual(service.activity.agentsToday, ["coder", "reviewer"])
        XCTAssertEqual(service.activity.workspacesToday, ["app"])
        XCTAssertEqual(service.activity.lastPromptAt, Date(timeIntervalSince1970: 1_788_606_000))
        XCTAssertTrue(service.activity.isLoggedIn)
        XCTAssertNil(service.lastError)
    }

    @MainActor func testMissingTokenMeansLoggedOut() async throws {
        try FileManager.default.removeItem(at: directory.appendingPathComponent("antigravity-oauth-token"))
        let service = service()
        await service.refresh()
        XCTAssertFalse(service.activity.isLoggedIn)
    }

    @MainActor func testEmptyTokenMeansLoggedOut() async throws {
        try Data().write(to: directory.appendingPathComponent("antigravity-oauth-token"))
        let service = service()
        await service.refresh()
        XCTAssertFalse(service.activity.isLoggedIn)
    }

    @MainActor func testMissingDatabaseKeepsPromptsCount() async throws {
        try FileManager.default.removeItem(at: database)
        let service = service()
        await service.refresh()
        XCTAssertEqual(service.activity.promptsToday, 2)
        XCTAssertEqual(service.activity.conversationsToday, 0)
        XCTAssertNil(service.lastError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: database.path))
    }

    @MainActor func testSqliteFailureKeepsPreviousActivity() async throws {
        let service = service()
        await service.refresh()
        let previous = service.activity
        try Data("not a database".utf8).write(to: database)
        await service.refresh()
        XCTAssertEqual(service.activity, previous)
        XCTAssertEqual(service.lastError, "sqlite3 exited 26")
        try FileManager.default.removeItem(at: database)
        await service.refresh()
        XCTAssertNil(service.lastError)
        XCTAssertEqual(service.activity.promptsToday, 2)
    }

    @MainActor func testDirectoryRemovalClearsActivity() async throws {
        let service = service()
        await service.refresh()
        try FileManager.default.removeItem(at: directory)
        await service.refresh()
        XCTAssertFalse(service.isInstalled)
        XCTAssertEqual(service.activity, GeminiActivity())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @MainActor func testLargeHistoryReadsTail() async throws {
        let line = "{\"timestamp\":1788602400000}\n"
        let content = line + String(repeating: "x", count: 6 * 1024 * 1024) + "\n" + line
        try content.write(to: directory.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)
        let service = service()
        await service.refresh()
        XCTAssertEqual(service.activity.promptsToday, 1)
        XCTAssertNil(service.lastError)
    }

    @MainActor func testRefreshDoesNotModifyDatabase() async throws {
        let before = try Data(contentsOf: database)
        let service = service()
        await service.refresh()
        XCTAssertEqual(try Data(contentsOf: database), before)
        XCTAssertNil(service.lastError)
    }
}
