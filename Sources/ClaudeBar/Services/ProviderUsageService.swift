import Foundation
import os

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

    private(set) var omlxCallsToday: Int = 0
    private(set) var isOmlxActive: Bool = false

    private var refreshTimer: Timer?

    private let projectsDir: String

    private static let codexDbPath: String = {
        let codexDir = NSString(string: "~/.codex").expandingTildeInPath
        let fm = FileManager.default
        // Pick the highest-numbered logs_N.sqlite (Codex increments the version over time)
        let best = (try? fm.contentsOfDirectory(atPath: codexDir))?
            .filter { $0.hasPrefix("logs_") && $0.hasSuffix(".sqlite") }
            .compactMap { name -> (path: String, n: Int)? in
                let stem = name.dropFirst(5).dropLast(7)   // strip "logs_" and ".sqlite"
                guard let n = Int(stem) else { return nil }
                return (codexDir + "/" + name, n)
            }
            .max(by: { $0.n < $1.n })
        return best?.path ?? (codexDir + "/logs_1.sqlite")
    }()

    private static let geminiCredsPath: String = {
        NSString(string: "~/.gemini/oauth_creds.json").expandingTildeInPath
    }()

    init(claudeDir: String = NSString(string: "~/.claude").expandingTildeInPath) {
        self.projectsDir = claudeDir + "/projects"
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
        await refreshOmlx()
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
            Log.providers.error("Codex DB query failed at \(dbPath, privacy: .private)")
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

    // MARK: - oMLX

    /// Scans today's JSONL session files for tool_use blocks calling any oMLX tool.
    /// Returns the count of distinct message IDs that contain at least one oMLX tool call.
    /// `nonisolated static` for testability.
    nonisolated static func countOmlxCallsInLines(_ lines: [String]) -> Int {
        var messageIDsWithOmlx: Set<String> = []

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["type"] as? String) == "assistant",
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]],
                  let msgID = message["id"] as? String else { continue }

            let hasOmlx = content.contains { block in
                guard (block["type"] as? String) == "tool_use",
                      let name = block["name"] as? String else { return false }
                return name.contains("omlx")
            }

            if hasOmlx {
                messageIDsWithOmlx.insert(msgID)
            }
        }
        return messageIDsWithOmlx.count
    }

    private func refreshOmlx() async {
        let projectsDir = self.projectsDir
        let fm = FileManager.default
        let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970

        let count = await Task.detached(priority: .utility) {
            var allLines: [String] = []

            guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else {
                return 0
            }

            for dir in projectDirs {
                let dirPath = projectsDir + "/" + dir
                for basePath in [dirPath, dirPath + "/subagents"] {
                    guard let files = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
                    for file in files where file.hasSuffix(".jsonl") {
                        let path = basePath + "/" + file
                        guard let attrs = try? fm.attributesOfItem(atPath: path),
                              let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970,
                              mtime >= todayStart else { continue }
                        guard let data = fm.contents(atPath: path),
                              let content = String(data: data, encoding: .utf8) else { continue }
                        allLines.append(contentsOf: content.split(separator: "\n").map(String.init))
                    }
                }
            }

            return ProviderUsageService.countOmlxCallsInLines(allLines)
        }.value

        omlxCallsToday = count
        isOmlxActive = count > 0
    }
}
