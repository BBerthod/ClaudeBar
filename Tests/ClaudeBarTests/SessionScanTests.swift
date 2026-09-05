import XCTest
@testable import ClaudeBarLib

@MainActor
final class SessionScanTests: XCTestCase {
    private func activeResult(_ id: String, value: Double) -> SessionService.ScanResult {
        .active(sessions: [ActiveSession(pid: 1, sessionId: id, cwd: "/tmp", startedAt: 1)],
                estimates: [id: value], resumeCost: [id: value * 2],
                lastActivity: [id: Date(timeIntervalSince1970: value)])
    }

    private func recentResult(_ id: String) -> SessionService.ScanResult {
        .recent([SessionIndexEntry(sessionId: id, fullPath: "/tmp/" + id,
                                   fileMtime: nil, firstPrompt: nil, summary: nil,
                                   messageCount: nil, created: nil, modified: nil,
                                   gitBranch: nil, projectPath: "/tmp", isSidechain: nil)])
    }

    func testOlderActiveScanCannotOverwriteNewerSnapshot() {
        let service = SessionService(disableMonitoring: true)
        let first = service.beginScan(.active)
        let second = service.beginScan(.active)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
        service.apply(activeResult("new", value: 0.8), generation: second)
        service.apply(activeResult("old", value: 0.2), generation: first)
        XCTAssertEqual(service.activeSessions.map(\.sessionId), ["new"])
        XCTAssertEqual(service.contextEstimates, ["new": 0.8])
        XCTAssertEqual(service.sessionResumeCost, ["new": 1.6])
        XCTAssertEqual(service.sessionLastActivity, ["new": Date(timeIntervalSince1970: 0.8)])
    }

    func testOlderRecentScanCannotOverwriteNewerSnapshot() {
        let service = SessionService(disableMonitoring: true)
        let first = service.beginScan(.recent)
        let second = service.beginScan(.recent)
        service.apply(recentResult("new"), generation: second)
        service.apply(recentResult("old"), generation: first)
        XCTAssertEqual(service.recentSessions.map(\.sessionId), ["new"])
    }

    func testScanIsObsoleteAsSoonAsNewScanStarts() {
        let service = SessionService(disableMonitoring: true)
        let active = service.beginScan(.active)
        let recent = service.beginScan(.recent)
        _ = service.beginScan(.active)
        _ = service.beginScan(.recent)
        service.apply(activeResult("old", value: 0.2), generation: active)
        service.apply(recentResult("old"), generation: recent)
        XCTAssertTrue(service.activeSessions.isEmpty)
        XCTAssertTrue(service.contextEstimates.isEmpty)
        XCTAssertTrue(service.sessionResumeCost.isEmpty)
        XCTAssertTrue(service.sessionLastActivity.isEmpty)
        XCTAssertTrue(service.recentSessions.isEmpty)
    }

    func testActiveAndRecentGenerationsAreIndependent() {
        let service = SessionService(disableMonitoring: true)
        let active = service.beginScan(.active)
        let recent = service.beginScan(.recent)
        _ = service.beginScan(.recent)
        service.apply(activeResult("active", value: 0.4), generation: active)
        XCTAssertEqual(service.activeSessions.map(\.sessionId), ["active"])
        _ = service.beginScan(.active)
        service.apply(recentResult("recent"), generation: recent + 1)
        XCTAssertEqual(service.recentSessions.map(\.sessionId), ["recent"])
    }
}
