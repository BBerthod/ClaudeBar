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
}
