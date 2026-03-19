import Foundation
import Security

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

    init() {
        loadCredentials()
        Task { await fetchUsage() }
        startPolling()
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

    /// Fraction of the 5h window elapsed (0.0–1.0).
    var fiveHourElapsedFraction: Double {
        guard let window = usage?.fiveHour else { return 0 }
        return elapsedFraction(for: window, windowHours: 5)
    }

    // MARK: - Polling

    private func startPolling() {
        // Poll every 60 seconds for usage data
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
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

    private func writeKeychain(service: String, credentials: KeychainCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
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
        guard let refreshTokenValue = cachedToken?.refreshToken else { return false }

        let url = URL(string: "https://console.anthropic.com/v1/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshTokenValue,
            "client_id": "cli"
        ]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
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

            // Persist to Keychain using the service name captured at load time
            if let service = keychainServiceName {
                let updated = KeychainCredentials(claudeAiOauth: newOAuthTokens)
                writeKeychain(service: service, credentials: updated)
            }

            return true
        } catch {
            return false
        }
    }

    // MARK: - API

    func fetchUsage() async {
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
                guard cachedToken != nil, !cachedToken!.isExpired else {
                    lastError = "Token expired — refresh failed"
                    return
                }
            }
        }

        guard let currentToken = cachedToken else {
            lastError = "Token lost after refresh"
            return
        }

        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(currentToken.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                return
            }

            if httpResponse.statusCode == 401 {
                // Token might be stale — reload from Keychain and retry once
                loadCredentials()
                lastError = "Auth failed (401)"
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
        } catch {
            lastError = error.localizedDescription
        }
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
