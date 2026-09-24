import XCTest
@testable import ClaudeBarLib

final class CostSourceTests: XCTestCase {
    func testTotalCostReturnsStatsCacheWhenPositive() {
        XCTAssertEqual(CostSource.totalCost(statsCache: 12.5, history: 8.0), 12.5)
    }

    func testTotalCostReturnsHistoryWhenStatsCacheIsZero() {
        XCTAssertEqual(CostSource.totalCost(statsCache: 0, history: 8.0), 8.0)
    }

    func testTotalCostReturnsZeroWhenBothAreZero() {
        XCTAssertEqual(CostSource.totalCost(statsCache: 0, history: 0), 0)
    }

    func testTrackedDaysUsesStatsCacheWhenPositiveOtherwiseHistory() {
        XCTAssertEqual(CostSource.trackedDays(statsCache: 5, history: 3), 5)
        XCTAssertEqual(CostSource.trackedDays(statsCache: 0, history: 3), 3)
        XCTAssertEqual(CostSource.trackedDays(statsCache: 0, history: 0), 0)
    }
}
