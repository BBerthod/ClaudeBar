import Foundation

@Observable
@MainActor
final class ProviderUsageService {
    private(set) var codexSessionsToday: Int = 0
    private(set) var codexTokensToday: Int = 0
    private(set) var codexLastModel: String? = nil
    private(set) var codexContextLimitHitsToday: Int = 0
    private(set) var isCodexAvailable: Bool = false

    private(set) var isGeminiAuthenticated: Bool = false
    private(set) var geminiTokenValid: Bool = false

    private var refreshTimer: Timer?

    private static let codexDbPath: String = {
        NSString(string: "~/.codex/logs_1.sqlite").expandingTildeInPath
    }()

    private static let geminiCredsPath: String = {
        NSString(string: "~/.gemini/oauth_creds.json").expandingTildeInPath
    }()

    init() {
        Task { await refresh() }
        startPolling()
    }

    // MARK: - Polling

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
    }

    // MARK: - Refresh

    func refresh() async {
        await refreshCodex()
        refreshGemini()
    }

    // MARK: - Codex

    private func refreshCodex() async {
        let dbPath = Self.codexDbPath
        guard FileManager.default.fileExists(atPath: dbPath) else {
            isCodexAvailable = false
            codexSessionsToday = 0
            codexTokensToday = 0
            codexLastModel = nil
            codexContextLimitHitsToday = 0
            return
        }

        // Compute local-timezone start-of-day to avoid SQLite's UTC strftime
        let localCutoff = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)

        let result = await Task.detached(priority: .utility) {
            ProviderUsageService.queryCodexDb(at: dbPath, startOfDayEpoch: localCutoff)
        }.value

        guard result.success else {
            isCodexAvailable = false
            codexSessionsToday = 0
            codexTokensToday = 0
            codexLastModel = nil
            codexContextLimitHitsToday = 0
            return
        }

        let parsed = result.rows.compactMap { Self.parseCodexRow($0) }

        var sessionMap: [String: (maxTokens: Int, model: String, limitHit: Bool)] = [:]
        for entry in parsed {
            if let existing = sessionMap[entry.processUUID] {
                let newMax = max(existing.maxTokens, entry.totalUsageTokens)
                let limitHit = existing.limitHit || entry.tokenLimitReached
                let model = entry.totalUsageTokens >= existing.maxTokens ? entry.model : existing.model
                sessionMap[entry.processUUID] = (maxTokens: newMax, model: model, limitHit: limitHit)
            } else {
                sessionMap[entry.processUUID] = (
                    maxTokens: entry.totalUsageTokens,
                    model: entry.model,
                    limitHit: entry.tokenLimitReached
                )
            }
        }

        let sessions = sessionMap.values
        isCodexAvailable = true
        codexSessionsToday = sessionMap.count
        codexTokensToday = sessions.reduce(0) { $0 + $1.maxTokens }
        codexContextLimitHitsToday = sessions.filter { $0.limitHit }.count

        // Query is ORDER BY ts DESC — parsed.first is the most recent entry.
        if let newestEntry = parsed.first {
            codexLastModel = sessionMap[newestEntry.processUUID]?.model
        } else {
            codexLastModel = nil
        }
    }

    private struct CodexEntry {
        let processUUID: String
        let totalUsageTokens: Int
        let model: String
        let tokenLimitReached: Bool
    }

    private static func parseCodexRow(_ row: String) -> CodexEntry? {
        let parts = row.components(separatedBy: "|")
        guard parts.count >= 3 else { return nil }
        let processUUID = parts[0]
        let body = parts[2]

        guard let totalUsageTokens = extractInt(from: body, key: "total_usage_tokens") else { return nil }
        let model = extractString(from: body, key: "model") ?? "unknown"
        let limitReachedStr = extractString(from: body, key: "token_limit_reached") ?? "false"
        let tokenLimitReached = limitReachedStr == "true"

        return CodexEntry(
            processUUID: processUUID,
            totalUsageTokens: totalUsageTokens,
            model: model,
            tokenLimitReached: tokenLimitReached
        )
    }

    private static func extractInt(from body: String, key: String) -> Int? {
        guard let range = body.range(of: "\(key)=") else { return nil }
        let after = body[range.upperBound...]
        let end = after.firstIndex(where: { !$0.isNumber }) ?? after.endIndex
        return Int(after[..<end])
    }

    private static func extractString(from body: String, key: String) -> String? {
        guard let range = body.range(of: "\(key)=") else { return nil }
        let after = body[range.upperBound...]
        let end = after.firstIndex(where: { $0 == " " || $0 == "}" || $0 == ")" || $0 == "," }) ?? after.endIndex
        let value = String(after[..<end])
        return value.isEmpty ? nil : value
    }

    private nonisolated static func queryCodexDb(
        at dbPath: String,
        startOfDayEpoch: Int
    ) -> (success: Bool, rows: [String]) {
        let query = """
        SELECT process_uuid, ts, feedback_log_body \
        FROM logs \
        WHERE feedback_log_body LIKE '%total_usage_tokens%' \
          AND ts >= \(startOfDayEpoch) \
        ORDER BY ts DESC \
        LIMIT 500
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-separator", "|", dbPath, query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return (success: false, rows: [])
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let rows = String(data: data, encoding: .utf8)?
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty } ?? []
            return (success: true, rows: rows)
        } catch {
            return (success: false, rows: [])
        }
    }

    // MARK: - Gemini

    private func refreshGemini() {
        let credsPath = Self.geminiCredsPath
        guard FileManager.default.fileExists(atPath: credsPath) else {
            isGeminiAuthenticated = false
            geminiTokenValid = false
            return
        }

        isGeminiAuthenticated = true

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: credsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiryDateMs = json["expiry_date"] as? Int64 else {
            geminiTokenValid = false
            return
        }

        let expiryDate = Date(timeIntervalSince1970: Double(expiryDateMs) / 1000.0)
        geminiTokenValid = expiryDate > Date()
    }
}
