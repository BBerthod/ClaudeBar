import XCTest
@testable import ClaudeBarLib

private final class UsageMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeUsageMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UsageMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func makeUsageResponse(status: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        statusCode: status,
        httpVersion: nil,
        headerFields: nil
    )!
}

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

    // MARK: - OAuth client ID

    /// Regression guard: the token endpoint rejects any client_id other than
    /// Claude Code's public OAuth client ID with HTTP 400, silently breaking
    /// token refresh. Verified live against console.anthropic.com/v1/oauth/token.
    func testOAuthClientIDMatchesClaudeCode() {
        XCTAssertEqual(UsageService.oauthClientID, "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
    }
}

@MainActor
final class UsageServiceNetworkTests: XCTestCase {
    func testConcurrentFetchesShareSingleRequest() async {
        let lock = NSLock()
        var requestCount = 0
        let responseData = """
        {
          "five_hour": { "utilization": 12.5, "resets_at": "2026-09-05T12:00:00Z" }
        }
        """.data(using: .utf8)!

        UsageMockURLProtocol.requestHandler = { _ in
            lock.withLock {
                requestCount += 1
            }
            Thread.sleep(forTimeInterval: 0.1)
            return (makeUsageResponse(), responseData)
        }

        let credentials = KeychainCredentials.OAuthTokens(
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            expiresAt: Int(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000),
            scopes: [],
            subscriptionType: nil,
            rateLimitTier: nil
        )
        let service = UsageService(
            session: makeUsageMockSession(),
            disablePolling: true,
            credentials: credentials
        )

        async let first: Void = service.fetchUsage()
        async let second: Void = service.fetchUsage()
        _ = await (first, second)

        let finalRequestCount = lock.withLock { requestCount }
        XCTAssertEqual(finalRequestCount, 1)
        XCTAssertEqual(service.usage?.fiveHour?.utilization, 12.5)
    }

    func testStaleWhenLastFetchExceedsThreePollingIntervals() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertFalse(UsageService.isStale(
            lastError: nil,
            lastFetched: now.addingTimeInterval(-899),
            now: now
        ))
        XCTAssertTrue(UsageService.isStale(
            lastError: nil,
            lastFetched: now.addingTimeInterval(-901),
            now: now
        ))
    }

    func testNotStaleBeforeFirstFetch() {
        XCTAssertFalse(UsageService.isStale(lastError: nil, lastFetched: nil))
    }

    func testErrorAlwaysMarksUsageStale() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(UsageService.isStale(
            lastError: "HTTP 500",
            lastFetched: now,
            now: now
        ))
    }
}
