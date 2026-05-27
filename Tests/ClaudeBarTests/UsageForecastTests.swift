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
}
