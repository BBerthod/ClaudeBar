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

    /// Short summary for the menu bar label.
    var menuBarLabel: String? {
        guard let fiveHour = usage?.fiveHour else { return nil }
        return "\(Int(fiveHour.utilization))%"
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
        if let creds = readKeychain(service: "Claude Code-credentials") {
            cachedToken = creds.claudeAiOauth
            plan = SubscriptionPlan(rawValue: creds.claudeAiOauth.subscriptionType ?? "unknown") ?? .unknown
            tier = RateLimitTier(raw: creds.claudeAiOauth.rateLimitTier)
            return
        }

        // Try discovering prefixed service names (Claude Code v2.1.52+)
        if let service = discoverKeychainService() {
            if let creds = readKeychain(service: service) {
                cachedToken = creds.claudeAiOauth
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
    private func discoverKeychainService() -> String? {
        // Run security dump-keychain and look for Claude Code-credentials-* entries
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["dump-keychain"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Find lines matching "svce"<blob>="Claude Code-credentials-XXXX"
        for line in output.components(separatedBy: "\n") {
            if line.contains("Claude Code-credentials-"),
               let start = line.range(of: "\"Claude Code-credentials-"),
               let end = line.range(of: "\"", range: start.upperBound..<line.endIndex) {
                let service = String(line[start.lowerBound..<end.upperBound])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return service
            }
        }

        return nil
    }

    // MARK: - API

    func fetchUsage() async {
        guard let token = cachedToken else {
            lastError = "No OAuth token found"
            return
        }

        // Check token expiry and refresh if needed
        if token.isExpired {
            loadCredentials()
            guard cachedToken != nil, !cachedToken!.isExpired else {
                lastError = "Token expired"
                return
            }
        }

        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(cachedToken!.accessToken)", forHTTPHeaderField: "Authorization")
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
