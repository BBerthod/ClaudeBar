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

private final class MemoryCredentialStore: CredentialStore {
    let service: String
    var data: Data
    var replacementOnNextRead: Data?
    var failWrites = false
    private(set) var writeCount = 0

    init(service: String = "Claude Code-credentials", data: Data) {
        self.service = service
        self.data = data
    }

    func readRaw(service: String) -> Data? {
        guard service == self.service else { return nil }
        if let replacementOnNextRead {
            data = replacementOnNextRead
            self.replacementOnNextRead = nil
        }
        return data
    }

    func writeRaw(_ data: Data, service: String) throws {
        XCTAssertEqual(service, self.service)
        writeCount += 1
        if failWrites { throw CocoaError(.fileWriteNoPermission) }
        self.data = data
    }

    func discoverService() -> String? { service }
}

@MainActor
final class UsageServiceCredentialPersistenceTests: XCTestCase {
    private func payload(access: String = "old-access", refresh: String = "old-refresh", expires: Int = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "foo": ["bar": 1],
            "other": [true, NSNull(), "preserve"],
            "claudeAiOauth": [
                "accessToken": access,
                "refreshToken": refresh,
                "expiresAt": expires,
                "scopes": ["user:profile", "user:inference"],
                "subscriptionType": "max",
                "rateLimitTier": "default_claude_max_20x",
                "unexpected": ["nested": [1, 2, 3]]
            ]
        ])
    }

    private func installResponses(expectedAccess: String) {
        UsageMockURLProtocol.requestHandler = { request in
            if request.url?.path == "/v1/oauth/token" {
                XCTAssertEqual(request.httpMethod, "POST")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#.utf8))
            }
            XCTAssertEqual(request.url?.path, "/api/oauth/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(expectedAccess)")
            return (makeUsageResponse(), Data(#"{"five_hour":{"utilization":12.5,"resets_at":"2026-09-05T12:00:00Z"}}"#.utf8))
        }
    }

    func testRefreshPreservesEntirePayloadForStandardAndDiscoveredServices() async throws {
        for serviceName in ["Claude Code-credentials", "Claude Code-credentials-prefixed"] {
            let original = try payload()
            let store = MemoryCredentialStore(service: serviceName, data: original)
            let session = makeUsageMockSession()
            defer { session.invalidateAndCancel(); UsageMockURLProtocol.requestHandler = nil }
            installResponses(expectedAccess: "new-access")
            let service = UsageService(session: session, disablePolling: true, credentialStore: store)
            let before = Int(Date().timeIntervalSince1970 * 1000) + 3_600_000
            await service.fetchUsage()
            let after = Int(Date().timeIntervalSince1970 * 1000) + 3_600_000

            XCTAssertNil(service.lastError)
            XCTAssertEqual(service.usage?.fiveHour?.utilization, 12.5)
            XCTAssertEqual(store.writeCount, 1)
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: store.data) as? [String: Any])
            let oauth = try XCTUnwrap(result["claudeAiOauth"] as? [String: Any])
            XCTAssertEqual(oauth["accessToken"] as? String, "new-access")
            XCTAssertEqual(oauth["refreshToken"] as? String, "new-refresh")
            let expiry = try XCTUnwrap(oauth["expiresAt"] as? Int)
            XCTAssertGreaterThanOrEqual(expiry, before)
            XCTAssertLessThanOrEqual(expiry, after)
            // Compare the complete object after restoring only the three changed fields.
            var restored = result
            var restoredOAuth = oauth
            restoredOAuth["accessToken"] = "old-access"
            restoredOAuth["refreshToken"] = "old-refresh"
            restoredOAuth["expiresAt"] = 1
            restored["claudeAiOauth"] = restoredOAuth
            let expected = try JSONSerialization.jsonObject(with: original) as! NSDictionary
            XCTAssertEqual(restored as NSDictionary, expected)
        }
    }

    func testWriteFailureKeepsRefreshedTokenInMemory() async throws {
        let original = try payload()
        let store = MemoryCredentialStore(data: original)
        store.failWrites = true
        let session = makeUsageMockSession()
        defer { session.invalidateAndCancel(); UsageMockURLProtocol.requestHandler = nil }
        installResponses(expectedAccess: "new-access")
        let service = UsageService(session: session, disablePolling: true, credentialStore: store)
        await service.fetchUsage()
        await service.fetchUsage()

        XCTAssertNil(service.lastError)
        XCTAssertEqual(service.usage?.fiveHour?.utilization, 12.5)
        XCTAssertEqual(store.writeCount, 1) // A second fetch used the unexpired cached token.
        XCTAssertEqual(store.data, original)
    }

    func testConcurrentClaudeCodeRefreshIsAdoptedWithoutWriting() async throws {
        let store = MemoryCredentialStore(data: try payload())
        let session = makeUsageMockSession()
        defer { session.invalidateAndCancel(); UsageMockURLProtocol.requestHandler = nil }
        installResponses(expectedAccess: "third-party-access")
        let service = UsageService(session: session, disablePolling: true, credentialStore: store)
        let thirdParty = try payload(
            access: "third-party-access", refresh: "third-party-refresh",
            expires: Int(Date().addingTimeInterval(7200).timeIntervalSince1970 * 1000)
        )
        // The initial read is complete; replace the item at the pre-write reread.
        store.replacementOnNextRead = thirdParty
        await service.fetchUsage()
        await service.fetchUsage()

        XCTAssertNil(service.lastError)
        XCTAssertEqual(service.usage?.fiveHour?.utilization, 12.5)
        XCTAssertEqual(store.writeCount, 0)
        XCTAssertEqual(store.data, thirdParty)
    }
}
