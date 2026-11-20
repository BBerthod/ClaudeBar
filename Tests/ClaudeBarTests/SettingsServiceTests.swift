import XCTest
@testable import ClaudeBarLib

// MARK: - SettingsServiceTests

@MainActor
final class SettingsServiceTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-service-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeSettings(_ json: String) throws {
        try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    }

    private func readSettings() throws -> [String: Any] {
        let data = try Data(contentsOf: dir.appendingPathComponent("settings.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testUnknownKeysSurviveSave() throws {
        try writeSettings("""
        {"effortLevel": "low", "model": "opus", "customFlag": {"nested": [1, 2]},
         "permissions": {"allow": ["Bash"], "defaultMode": "plan"}}
        """)
        let service = SettingsService(claudeDir: dir.path)
        service.setEffortLevel("high")

        let saved = try readSettings()
        XCTAssertEqual(saved["effortLevel"] as? String, "high")
        XCTAssertEqual(saved["model"] as? String, "opus")
        XCTAssertEqual((saved["customFlag"] as? [String: Any])?["nested"] as? [Int], [1, 2])
        let permissions = try XCTUnwrap(saved["permissions"] as? [String: Any])
        XCTAssertEqual(permissions["defaultMode"] as? String, "plan")
        XCTAssertEqual(permissions["allow"] as? [String], ["Bash"])
    }

    func testMissingFileIsCreated() throws {
        let service = SettingsService(claudeDir: dir.path)
        service.setThinkingEnabled(true)
        XCTAssertEqual(try readSettings()["alwaysThinkingEnabled"] as? Bool, true)
    }
}
