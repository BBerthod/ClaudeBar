import Testing
@testable import ClaudeBarLib

struct ContextAlertDecisionTests {
    @Test
    func armedCrossingAlertsAndDisarms() {
        let decision = NotificationService.contextAlertDecision(
            fraction: 0.92,
            thresholdFraction: 0.90,
            armed: true
        )

        #expect(decision.shouldAlert)
        #expect(!decision.armed)
    }

    @Test
    func disarmedStillHighDoesNotAlert() {
        let decision = NotificationService.contextAlertDecision(
            fraction: 0.92,
            thresholdFraction: 0.90,
            armed: false
        )

        #expect(!decision.shouldAlert)
        #expect(!decision.armed)
    }

    @Test
    func disarmedDropBelowRearmRearms() {
        let decision = NotificationService.contextAlertDecision(
            fraction: 0.65,
            thresholdFraction: 0.90,
            armed: false
        )

        #expect(!decision.shouldAlert)
        #expect(decision.armed)
    }

    @Test
    func rearmedNewCrossingAlertsAndDisarms() {
        let decision = NotificationService.contextAlertDecision(
            fraction: 0.91,
            thresholdFraction: 0.90,
            armed: true
        )

        #expect(decision.shouldAlert)
        #expect(!decision.armed)
    }

    @Test
    func armedBelowThresholdStaysArmed() {
        let decision = NotificationService.contextAlertDecision(
            fraction: 0.50,
            thresholdFraction: 0.90,
            armed: true
        )

        #expect(!decision.shouldAlert)
        #expect(decision.armed)
    }

    @Test
    func lowThresholdRearmClampsToZero() {
        let decision = NotificationService.contextAlertDecision(
            fraction: 0.05,
            thresholdFraction: 0.10,
            armed: false
        )

        #expect(!decision.shouldAlert)
        #expect(!decision.armed)
    }
}
