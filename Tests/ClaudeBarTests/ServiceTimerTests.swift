import XCTest
@testable import ClaudeBarLib

@MainActor
final class ServiceTimerTests: XCTestCase {
    /// Keep the scheduled timer alive to verify invalidation independently of deallocation.
    private func scheduledTimer(in service: AnyObject) throws -> Timer {
        let timers = Mirror(reflecting: service).children.compactMap { child -> Timer? in
            (child.value as? ServiceTimer)?.timer
        }
        XCTAssertEqual(timers.count, 1)
        return try XCTUnwrap(timers.first)
    }

    func testTimerReplacementInvalidatesPreviousTimer() {
        let owner = ServiceTimer()
        let first = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in }
        let second = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in }
        defer { first.invalidate(); second.invalidate() }
        owner.timer = first
        owner.timer = second
        XCTAssertFalse(first.isValid)
        XCTAssertTrue(second.isValid)
        owner.invalidate()
        XCTAssertFalse(second.isValid)
        XCTAssertNil(owner.timer)
    }

    /// The init kicks off detached scans that briefly retain `self` while hopping back to
    /// the main actor; spin the run loop so deallocation can actually happen.
    private func waitForInvalidation(of timer: Timer) {
        let deadline = Date().addingTimeInterval(2)
        while timer.isValid && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    func testSessionServiceInvalidatesTimerOnDeinit() throws {
        var service: SessionService? = SessionService(claudeDir: "/nonexistent/claudebar-timer-test")
        let timer = try scheduledTimer(in: XCTUnwrap(service))
        XCTAssertTrue(timer.isValid)
        service = nil
        waitForInvalidation(of: timer)
        XCTAssertFalse(timer.isValid)
    }

    func testNotificationServiceInvalidatesTimerOnDeinit() throws {
        var service: NotificationService? = NotificationService()
        let timer = try scheduledTimer(in: XCTUnwrap(service))
        XCTAssertTrue(timer.isValid)
        service = nil
        waitForInvalidation(of: timer)
        XCTAssertFalse(timer.isValid)
    }
}
