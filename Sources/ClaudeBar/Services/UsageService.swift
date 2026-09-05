import Foundation
import Security
import os

/// Fetches real-time usage/rate-limit data from the Anthropic OAuth API.
@Observable
@MainActor
final class UsageService {
    private(set) var usage: UsageResponse?
    private(set) var plan: SubscriptionPlan = .unknown
    private(set) var tier: RateLimitTier = .other("unknown")
    private(set) var lastError: String?
    private(set) var lastFetched: Date?

    private var refreshTimer: Timer?
    private var cachedToken: KeychainCredentials.OAuthTokens?
    private var keychainServiceName: String?
    private var retryAfter: Date?
    private let session: URLSession
    private var fetchTask: (id: UUID, task: Task<Void, Never>)?
    private var tokenRefreshTask: (id: UUID, task: Task<Bool, Never>)?

    private static let pollingInterval: TimeInterval = 300
    nonisolated private static let staleInterval: TimeInterval = 900

    /// Public OAuth client ID used by Claude Code. The token endpoint rejects any
    /// other value with HTTP 400 "Invalid request format", which silently breaks
    /// token refresh. Must match the value Claude Code itself uses.
    nonisolated static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    init(
        session: URLSession = .shared,
        disablePolling: Bool = false,
        credentials: KeychainCredentials.OAuthTokens? = nil
    ) {
        self.session = session
        if let credentials {
            cachedToken = credentials
        } else {
            loadCredentials()
        }
        if !disablePolling {
            Task { await fetchUsage() }
            startPolling()
        }
    }

    // MARK: - Computed

    var fiveHourPace: PaceLevel? {
        guard let window = usage?.fiveHour else { return nil }
        let elapsed = elapsedFraction(for: window, windowHours: 5)
        return PaceLevel(utilization: window.utilization, elapsedFraction: elapsed)
    }

    var sevenDayPace: PaceLevel? {
        guard let window = usage?.sevenDay else { return nil }
        let elapsed = elapsedFraction(for: window, windowHours: 168)
        return PaceLevel(utilization: window.utilization, elapsedFraction: elapsed)
    }

    var isStale: Bool {
        Self.isStale(lastError: lastError, lastFetched: lastFetched)
    }

    nonisolated static func isStale(
        lastError: String?,
        lastFetched: Date?,
        now: Date = Date()
    ) -> Bool {
        if lastError != nil { return true }
        // No fetch yet (start-up, request in flight): nothing to be stale about.
        guard let lastFetched else { return false }
        return now.timeIntervalSince(lastFetched) > staleInterval
    }

    /// Extracted for testability.
    nonisolated static func estimatedHoursUntilLimit(window: UsageWindow) -> Double? {
        guard let resetDate = window.resetDate else { return nil }
        let percentUsed = window.utilization / 100.0
        guard percentUsed < 1.0 else { return nil }
        guard percentUsed > 0.0 else { return nil }

        let windowStart = resetDate.addingTimeInterval(-5 * 3600)
        let elapsed = max(Date().timeIntervalSince(windowStart), 1)
        let elapsedHours = elapsed / 3600

        let ratePerHour = percentUsed / elapsedHours
        guard ratePerHour >= 0.0001 else { return nil }

        let hoursToFull = (1.0 - percentUsed) / ratePerHour
        let hoursUntilReset = resetDate.timeIntervalSince(Date()) / 3600
        guard hoursToFull <= hoursUntilReset else { return nil }

        return hoursToFull
    }

    /// Estimated hours until the 5h window hits 100%, based on current burn rate.
    /// Returns nil if data is insufficient or rate is near-zero.
    var estimatedHoursUntilLimit: Double? {
        guard let window = usage?.fiveHour else { return nil }
        return UsageService.estimatedHoursUntilLimit(window: window)
    }

    /// Fraction of the 5h window elapsed (0.0–1.0).
    var fiveHourElapsedFraction: Double {
        guard let window = usage?.fiveHour else { return 0 }
        return elapsedFraction(for: window, windowHours: 5)
    }

    // MARK: - Polling

    private func startPolling() {
        // Poll every 5 minutes — the usage endpoint is rate-limited by Anthropic
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.pollingInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchUsage()
            }
        }
    }

    // MARK: - Keychain

    private func loadCredentials() {
        // Try standard service name first
        let standardService = "Claude Code-credentials"
        if let creds = readKeychain(service: standardService) {
            cachedToken = creds.claudeAiOauth
            keychainServiceName = standardService
            plan = SubscriptionPlan(rawValue: creds.claudeAiOauth.subscriptionType ?? "unknown") ?? .unknown
            tier = RateLimitTier(raw: creds.claudeAiOauth.rateLimitTier)
            return
        }

        // Try discovering prefixed service names (Claude Code v2.1.52+)
        if let service = discoverKeychainService() {
            if let creds = readKeychain(service: service) {
                cachedToken = creds.claudeAiOauth
                keychainServiceName = service
                plan = SubscriptionPlan(rawValue: creds.claudeAiOauth.subscriptionType ?? "unknown") ?? .unknown
                tier = RateLimitTier(raw: creds.claudeAiOauth.rateLimitTier)
            }
        }
    }

    private func readKeychain(service: String) -> KeychainCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(KeychainCredentials.self, from: data)
    }

    /// Discovers the prefixed Keychain service name used by newer Claude Code versions.
    /// Uses SecItemCopyMatching to search for matching entries instead of dumping
    /// the entire keychain via the `security` CLI.
    private func discoverKeychainService() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return nil
        }

        for item in items {
            guard let service = item[kSecAttrService as String] as? String,
                  service.hasPrefix("Claude Code-credentials-") else { continue }
            return service
        }

        return nil
    }

    // MARK: - Token Refresh

    private struct TokenRefreshResponse: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private func refreshToken() async -> Bool {
        if let tokenRefreshTask {
            return await tokenRefreshTask.task.value
        }

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performTokenRefresh()
        }
        tokenRefreshTask = (id, task)
        let result = await task.value
        if tokenRefreshTask?.id == id {
            tokenRefreshTask = nil
        }
        return result
    }

    private func performTokenRefresh() async -> Bool {
        guard let refreshTokenValue = cachedToken?.refreshToken else { return false }

        let url = URL(string: "https://console.anthropic.com/v1/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshTokenValue,
            "client_id": UsageService.oauthClientID
        ]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return false }

            let decoded = try JSONDecoder().decode(TokenRefreshResponse.self, from: data)

            // expiresAt is in milliseconds
            let expiresAt = Int(Date().timeIntervalSince1970 * 1000) + (decoded.expiresIn * 1000)

            let oldToken = cachedToken
            let newOAuthTokens = KeychainCredentials.OAuthTokens(
                accessToken: decoded.accessToken,
                refreshToken: decoded.refreshToken,
                expiresAt: expiresAt,
                scopes: oldToken?.scopes ?? [],
                subscriptionType: oldToken?.subscriptionType,
                rateLimitTier: oldToken?.rateLimitTier
            )

            cachedToken = newOAuthTokens
            Log.usage.info("OAuth token refreshed successfully")
            return true
        } catch {
            Log.usage.error("Token refresh failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - API

    func fetchUsage() async {
        if let fetchTask {
            await fetchTask.task.value
            return
        }

        let id = UUID()
        let task = Task { @MainActor [weak self] () -> Void in
            guard let self else { return }
            await self.performFetchUsage()
        }
        fetchTask = (id, task)
        await task.value
        if fetchTask?.id == id {
            fetchTask = nil
        }
    }

    private func performFetchUsage() async {
        // Respect backoff from a previous 429
        if let until = retryAfter, Date() < until { return }

        guard let token = cachedToken else {
            lastError = "No OAuth token found"
            return
        }

        // Check token expiry and refresh if needed
        if token.isExpired {
            let refreshed = await refreshToken()
            if !refreshed {
                // Fallback: Claude Code might have refreshed it in the meantime
                loadCredentials()
                guard let refreshed = cachedToken, !refreshed.isExpired else {
                    lastError = "Token expired — refresh failed"
                    return
                }
            }
        }

        guard var currentToken = cachedToken else {
            lastError = "Token lost after refresh"
            return
        }

        do {
            var (data, httpResponse) = try await requestUsage(with: currentToken)

            if httpResponse.statusCode == 401 {
                // Token might be stale — reload from Keychain and retry once
                let rejectedAccessToken = currentToken.accessToken
                loadCredentials()

                guard var reloadedToken = cachedToken else {
                    lastError = "Auth failed (401) — no OAuth token found"
                    return
                }

                if reloadedToken.isExpired || reloadedToken.accessToken == rejectedAccessToken {
                    guard await refreshToken(), let refreshedToken = cachedToken else {
                        lastError = "Auth failed (401) — token refresh failed"
                        return
                    }
                    reloadedToken = refreshedToken
                }

                currentToken = reloadedToken
                (data, httpResponse) = try await requestUsage(with: currentToken)
                guard httpResponse.statusCode != 401 else {
                    lastError = "Auth failed (401) after retry"
                    return
                }
            }

            if httpResponse.statusCode == 429 {
                // Back off for 10 minutes when rate-limited
                retryAfter = Date().addingTimeInterval(600)
                lastError = "Rate limited — retrying in 10 min"
                Log.usage.error("Usage API rate limited (429) — backing off 10 min")
                return
            }

            guard httpResponse.statusCode == 200 else {
                lastError = "HTTP \(httpResponse.statusCode)"
                return
            }

            let decoder = JSONDecoder()
            usage = try decoder.decode(UsageResponse.self, from: data)
            lastError = nil
            lastFetched = Date()
            Log.usage.info("Usage fetched — 5h: \(self.usage?.fiveHour?.utilization ?? 0, format: .fixed(precision: 1))%")
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func requestUsage(
        with token: KeychainCredentials.OAuthTokens
    ) async throws -> (Data, HTTPURLResponse) {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }

    // MARK: - Helpers

    /// Estimates how far we are into a time window (0.0 – 1.0).
    private func elapsedFraction(for window: UsageWindow, windowHours: Double) -> Double {
        guard let resetDate = window.resetDate else { return 0.5 }
        let windowSeconds = windowHours * 3600
        let remaining = resetDate.timeIntervalSince(Date())
        let elapsed = windowSeconds - remaining
        return max(0, min(1, elapsed / windowSeconds))
    }
}
