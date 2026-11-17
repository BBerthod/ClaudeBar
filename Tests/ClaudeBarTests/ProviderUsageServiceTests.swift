import XCTest
@testable import ClaudeBarLib

final class ProviderUsageServiceTests: XCTestCase {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    func testOutputLargerThanPipeBufferIsDrainedWhileRunning() async throws {
        let start = Date()
        let data = await ProviderUsageService.runCapturingOutput(
            executableURL: shell, arguments: ["-c", "head -c 2000000 /dev/zero | tr '\\000' a"], timeout: 10)
        XCTAssertEqual(data?.count, 2_000_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testTimeoutTerminatesHungProcessAndFails() async throws {
        let start = Date()
        let data = await ProviderUsageService.runCapturingOutput(
            executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["60"], timeout: 0.3)
        XCTAssertNil(data)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testProcessIgnoringSigtermIsKilled() async throws {
        let start = Date()
        let data = await ProviderUsageService.runCapturingOutput(
            executableURL: shell, arguments: ["-c", "trap '' TERM; exec /bin/sleep 60"],
            timeout: 0.3, killGrace: 0.5)
        XCTAssertNil(data)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testNonZeroExitFails() async throws {
        let data = await ProviderUsageService.runCapturingOutput(
            executableURL: shell, arguments: ["-c", "echo partial; exit 3"], timeout: 5)
        XCTAssertNil(data)
    }

    /// Fake Codex query: counts calls and stays suspended until `release()`.
    private actor QueryGate {
        private(set) var calls = 0
        private var released = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func enter() async {
            calls += 1
            guard !released else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func release() {
            released = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    @MainActor
    func testConcurrentRefreshesRunASingleCodexQuery() async throws {
        let dbFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-test-\(UUID().uuidString).sqlite")
        XCTAssertTrue(FileManager.default.createFile(atPath: dbFile.path, contents: Data()))
        defer { try? FileManager.default.removeItem(at: dbFile) }

        let gate = QueryGate()
        let service = ProviderUsageService(
            codexDbPath: dbFile.path,
            codexQuery: { _, _ in
                await gate.enter()
                return (success: true, rows: [])
            },
            disablePolling: true)

        let first = Task { await service.refresh() }
        while await gate.calls == 0 { await Task.yield() }

        // Second refresh while the first query is still suspended: the guard must skip it.
        // Not awaited directly: without the guard it would hang on the gate instead of failing.
        let second = Task { await service.refresh() }
        for _ in 0..<50 { await Task.yield() }
        let callsWhileInFlight = await gate.calls
        XCTAssertEqual(callsWhileInFlight, 1)

        await gate.release()
        await first.value
        await second.value

        // The guard is released once the query ends: a later refresh queries again.
        await service.refresh()
        let callsAfterRelease = await gate.calls
        XCTAssertEqual(callsAfterRelease, 2)
    }
}
