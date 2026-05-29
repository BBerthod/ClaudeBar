import Testing
@testable import ClaudeBarLib

struct UsageForecastTests {

    @Test
    func testSecondsToLimitProjectsFromCurrentPace() {
        let seconds = UsageForecast.secondsToLimit(utilization: 50, elapsedFraction: 0.5)

        #expect(abs((seconds ?? 0) - 9_000) <= 60)
    }

    @Test
    func testSecondsToLimitReturnsNilWhenForecastIsNotMeaningful() {
        #expect(UsageForecast.secondsToLimit(utilization: 0.5, elapsedFraction: 0.5) == nil)
        #expect(UsageForecast.secondsToLimit(utilization: 100, elapsedFraction: 0.5) == nil)
        #expect(UsageForecast.secondsToLimit(utilization: 50, elapsedFraction: 0.01) == nil)
    }

    @Test
    func testLimitLabelWhenLimitFallsAfterReset() {
        let label = UsageForecast.limitLabel(
            utilization: 50,
            elapsedFraction: 0.5,
            secondsRemaining: 1_000
        )

        #expect(label == "pas avant le reset")
    }

    @Test
    func testLimitLabelFormatting() {
        let label = UsageForecast.limitLabel(
            utilization: 55,
            elapsedFraction: 0.4,
            secondsRemaining: 100_000
        )

        #expect(label == "≈ limite dans 1h38")
    }

    @Test
    func testIsUrgentWhenLimitIsBeforeResetAndUnderThreshold() {
        let urgent = UsageForecast.isUrgent(
            utilization: 80,
            elapsedFraction: 0.8,
            secondsRemaining: 100_000
        )

        #expect(urgent)
    }

    @Test
    func testIsUrgentFalseWhenLimitFallsAfterReset() {
        let urgent = UsageForecast.isUrgent(
            utilization: 50,
            elapsedFraction: 0.5,
            secondsRemaining: 1_000
        )

        #expect(!urgent)
    }

    @Test
    func testIsUrgentFalseWhenLimitIsOverThreshold() {
        let urgent = UsageForecast.isUrgent(
            utilization: 20,
            elapsedFraction: 0.5,
            secondsRemaining: 100_000
        )

        #expect(!urgent)
    }

    // MARK: - compactDuration

    @Test
    func testCompactDurationFormatting() {
        #expect(UsageForecast.compactDuration(7_200) == "2h00")
        #expect(UsageForecast.compactDuration(5_890) == "1h38")
        #expect(UsageForecast.compactDuration(3_600) == "1h00")
        #expect(UsageForecast.compactDuration(2_280) == "38m")
        #expect(UsageForecast.compactDuration(65) == "1m")
        #expect(UsageForecast.compactDuration(-5) == "0m")
    }

    // MARK: - statusBarText

    @Test
    func testStatusBarTextCalmShowsResetOnly() {
        // Limit projected far past the reset → only the reset countdown shows.
        let text = UsageForecast.statusBarText(
            utilization: 20,
            elapsedFraction: 0.5,
            secondsRemaining: 7_200
        )

        #expect(text == "↻2h00")
    }

    @Test
    func testStatusBarTextLoadedShowsForecastAndReset() {
        // Same pace as testLimitLabelFormatting (1h38 to limit), reset in 2h30.
        let text = UsageForecast.statusBarText(
            utilization: 55,
            elapsedFraction: 0.4,
            secondsRemaining: 9_000
        )

        #expect(text == "~1h38 → ↻2h30")
    }

    @Test
    func testStatusBarTextResettingWhenNoTimeLeft() {
        let text = UsageForecast.statusBarText(
            utilization: 95,
            elapsedFraction: 0.9,
            secondsRemaining: 0
        )

        #expect(text == "↻…")
    }
}
