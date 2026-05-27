import Foundation
import Testing
@testable import ClaudeBarLib

struct IdleSessionTests {

    @Test func fiveHoursAgoReturnsIdleHoursLabel() {
        let now = Date(timeIntervalSince1970: 10_000)
        let lastActivity = now.addingTimeInterval(-5 * 3600)

        #expect(SessionService.idleLabel(lastActivity: lastActivity, now: now) == "idle 5h")
    }

    @Test func twoHoursAgoBelowDefaultThresholdReturnsNil() {
        let now = Date(timeIntervalSince1970: 10_000)
        let lastActivity = now.addingTimeInterval(-2 * 3600)

        #expect(SessionService.idleLabel(lastActivity: lastActivity, now: now) == nil)
    }

    @Test func exactlyFourHoursAgoReturnsIdleHoursLabel() {
        let now = Date(timeIntervalSince1970: 10_000)
        let lastActivity = now.addingTimeInterval(-4 * 3600)

        #expect(SessionService.idleLabel(lastActivity: lastActivity, now: now) == "idle 4h")
    }

    @Test func fiftyHoursAgoReturnsIdleDaysLabel() {
        let now = Date(timeIntervalSince1970: 200_000)
        let lastActivity = now.addingTimeInterval(-50 * 3600)

        #expect(SessionService.idleLabel(lastActivity: lastActivity, now: now) == "idle 2j")
    }

    @Test func customThresholdUsesElapsedHours() {
        let now = Date(timeIntervalSince1970: 10_000)
        let lastActivity = now.addingTimeInterval(-90 * 60)

        #expect(SessionService.idleLabel(lastActivity: lastActivity, now: now, threshold: 3600) == "idle 1h")
    }
}
