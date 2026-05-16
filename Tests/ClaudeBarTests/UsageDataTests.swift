import XCTest
@testable import ClaudeBarLib

final class OAuthTokensExpiryTests: XCTestCase {

    func testExpiredToken() {
        // expiresAt in the past (Unix ms)
        let past = Int(Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000)
        let token = KeychainCredentials.OAuthTokens(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: past,
            scopes: [],
            subscriptionType: nil,
            rateLimitTier: nil
        )
        XCTAssertTrue(token.isExpired)
    }

    func testValidToken() {
        // expiresAt in the future
        let future = Int(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000)
        let token = KeychainCredentials.OAuthTokens(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: future,
            scopes: [],
            subscriptionType: nil,
            rateLimitTier: nil
        )
        XCTAssertFalse(token.isExpired)
    }
}

final class UsageWindowTests: XCTestCase {

    func testResetDateValidISO() {
        let window = UsageWindow(utilization: 50, resetsAt: "2026-05-16T18:00:00Z")
        XCTAssertNotNil(window.resetDate)
    }

    func testResetDateValidISOWithFractionalSeconds() {
        let window = UsageWindow(utilization: 50, resetsAt: "2026-05-16T18:00:00.000Z")
        XCTAssertNotNil(window.resetDate)
    }

    func testResetDateInvalidReturnsNil() {
        let window = UsageWindow(utilization: 50, resetsAt: "not-a-date")
        XCTAssertNil(window.resetDate)
    }

    func testTimeRemainingNilWhenInvalidDate() {
        let window = UsageWindow(utilization: 50, resetsAt: "bad")
        XCTAssertNil(window.timeRemaining)
    }

    func testTimeRemainingResettingWhenPast() {
        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        let window = UsageWindow(utilization: 100, resetsAt: past)
        XCTAssertEqual(window.timeRemaining, "resetting…")
    }
}

final class RateLimitTierTests: XCTestCase {

    func testMax20x() {
        XCTAssertEqual(RateLimitTier(raw: "max_20x").displayName, "Max 20x")
    }

    func testMax5x() {
        XCTAssertEqual(RateLimitTier(raw: "max_5x").displayName, "Max 5x")
    }

    func testPro() {
        XCTAssertEqual(RateLimitTier(raw: "pro").displayName, "Pro")
    }

    func testUnknownPassthrough() {
        XCTAssertEqual(RateLimitTier(raw: "enterprise_custom").displayName, "enterprise_custom")
    }

    func testNilRaw() {
        if case .other(let s) = RateLimitTier(raw: nil) {
            XCTAssertEqual(s, "unknown")
        } else {
            XCTFail("Expected .other(\"unknown\")")
        }
    }
}
