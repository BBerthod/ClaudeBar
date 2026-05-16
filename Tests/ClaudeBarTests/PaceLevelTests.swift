import XCTest
@testable import ClaudeBarLib

final class PaceLevelTests: XCTestCase {

    func testComfortableWhenWindowTooEarly() {
        // elapsedFraction <= 0.05 → always comfortable regardless of utilization
        XCTAssertEqual(PaceLevel(utilization: 99, elapsedFraction: 0.01), .comfortable)
        XCTAssertEqual(PaceLevel(utilization: 50, elapsedFraction: 0.05), .comfortable)
    }

    func testComfortable() {
        // projected = 20 / 0.5 = 40 → < 50 → comfortable
        XCTAssertEqual(PaceLevel(utilization: 20, elapsedFraction: 0.5), .comfortable)
    }

    func testOnTrack() {
        // projected = 30 / 0.5 = 60 → [50, 75) → onTrack
        XCTAssertEqual(PaceLevel(utilization: 30, elapsedFraction: 0.5), .onTrack)
    }

    func testWarming() {
        // projected = 40 / 0.5 = 80 → [75, 90) → warming
        XCTAssertEqual(PaceLevel(utilization: 40, elapsedFraction: 0.5), .warming)
    }

    func testPressing() {
        // projected = 46 / 0.5 = 92 → [90, 100) → pressing
        XCTAssertEqual(PaceLevel(utilization: 46, elapsedFraction: 0.5), .pressing)
    }

    func testCritical() {
        // projected = 55 / 0.5 = 110 → [100, 120) → critical
        XCTAssertEqual(PaceLevel(utilization: 55, elapsedFraction: 0.5), .critical)
    }

    func testRunaway() {
        // projected = 80 / 0.5 = 160 → >= 120 → runaway
        XCTAssertEqual(PaceLevel(utilization: 80, elapsedFraction: 0.5), .runaway)
    }

    func testExactly100PercentAtHalfWindow() {
        // projected = 50 / 0.5 = 100 → critical (100 is the lower bound)
        XCTAssertEqual(PaceLevel(utilization: 50, elapsedFraction: 0.5), .critical)
    }

    func testOnTrackAtExactly50Percent() {
        // 50 / 1.0 = 50 → borne inférieure de onTrack
        XCTAssertEqual(PaceLevel(utilization: 50, elapsedFraction: 1.0), .onTrack)
    }

    func testElapsedFractionZeroIsComfortable() {
        // garde elapsedFraction <= 0.05 → comfortable quelle que soit l'utilisation
        XCTAssertEqual(PaceLevel(utilization: 99, elapsedFraction: 0.0), .comfortable)
    }
}
