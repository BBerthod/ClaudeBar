import XCTest
@testable import ClaudeBarLib

final class UsageServiceEstimatedHoursTests: XCTestCase {

    // MARK: - Helpers

    private func makeResetsAt(hoursFromNow: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date().addingTimeInterval(hoursFromNow * 3600))
    }

    // MARK: - Tests

    /// utilization=0 → guard percentUsed > 0.0 fires → nil.
    func testNilWhenZeroUtilization() {
        let window = UsageWindow(utilization: 0, resetsAt: makeResetsAt(hoursFromNow: 3))
        XCTAssertNil(UsageService.estimatedHoursUntilLimit(window: window))
    }

    /// utilization=100 → guard percentUsed < 1.0 fires → nil.
    func testNilWhenAlreadyAtLimit() {
        let window = UsageWindow(utilization: 100, resetsAt: makeResetsAt(hoursFromNow: 3))
        XCTAssertNil(UsageService.estimatedHoursUntilLimit(window: window))
    }

    /// Invalid resetsAt string → resetDate is nil → nil.
    func testNilWhenInvalidDate() {
        let window = UsageWindow(utilization: 50, resetsAt: "invalid")
        XCTAssertNil(UsageService.estimatedHoursUntilLimit(window: window))
    }

    /// Window resets in 4h, utilization=50%.
    /// Window started 1h ago (5h - 4h remaining = 1h elapsed).
    /// rate = 50% / 1h = 50%/h → hoursToFull = 50 / 50 = 1h.
    /// hoursToFull (1h) <= hoursUntilReset (4h) → returns ~1h.
    func testProjectionWithinWindow() {
        let window = UsageWindow(utilization: 50, resetsAt: makeResetsAt(hoursFromNow: 4))
        let result = UsageService.estimatedHoursUntilLimit(window: window)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 1.0, accuracy: 0.05)
    }

    /// Window resets in 1h, utilization=10%.
    /// Window started 4h ago (5h - 1h remaining = 4h elapsed).
    /// rate = 10% / 4h = 2.5%/h → hoursToFull = 90 / 2.5 = 36h.
    /// hoursToFull (36h) > hoursUntilReset (1h) → nil.
    func testNilWhenProjectedBeyondReset() {
        let window = UsageWindow(utilization: 10, resetsAt: makeResetsAt(hoursFromNow: 1))
        XCTAssertNil(UsageService.estimatedHoursUntilLimit(window: window))
    }
}
