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

    private nonisolated let refreshTimer = ServiceTimer()
    private var isRefreshingCodex = false

    /// Upper bound for one sqlite3 run; past it the query is killed and counted as failed.
    private nonisolated static let codexQueryTimeout: TimeInterval = 25

    deinit {
        refreshTimer.invalidate()
    }

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

    init() {
        Task { await refresh() }
        startPolling()
    }

    // MARK: - Polling

    private func startPolling() {
        refreshTimer.timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
    }

    // MARK: - Refresh

    func refresh() async {
        await refreshCodex()
    }

    // MARK: - Codex

    private func refreshCodex() async {
        // The 300 s timer must not stack a new query on top of one still running.
        guard !isRefreshingCodex else { return }
        isRefreshingCodex = true
        defer { isRefreshingCodex = false }
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

        let result = await Self.queryCodexDb(at: dbPath, startOfDayEpoch: localCutoff)

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
    ) async -> (success: Bool, rows: [String]) {
        // The ts bound is served by idx_logs_ts; LIKE only runs on today's rows.
        let query = """
        SELECT process_uuid, ts, feedback_log_body \
        FROM logs \
        WHERE feedback_log_body LIKE '%total_usage_tokens%' \
          AND ts >= \(startOfDayEpoch) \
        ORDER BY ts DESC \
        LIMIT 500
        """
        // -readonly: never write to (or checkpoint) the database Codex is writing.
        // No immutable=1: Codex keeps recent rows in the WAL.
        guard let data = await runCapturingOutput(
            executableURL: URL(fileURLWithPath: "/usr/bin/sqlite3"),
            arguments: ["-readonly", "-separator", "|", dbPath, query],
            timeout: codexQueryTimeout
        ) else {
            return (success: false, rows: [])
        }
        let rows = String(data: data, encoding: .utf8)?
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty } ?? []
        return (success: true, rows: rows)
    }

    /// Runs an executable and returns its stdout, or nil on launch failure, non-zero exit or timeout.
    ///
    /// Stdout is drained while the process runs: output larger than the pipe buffer
    /// (~64 KB) would otherwise block the child on write forever. Past `timeout` the
    /// process gets SIGTERM, then SIGKILL `killGrace` seconds later.
    /// The blocking read runs on a GCD thread, never on a Swift Concurrency cooperative
    /// thread: blocking those starves every task in the app.
    nonisolated static func runCapturingOutput(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        killGrace: TimeInterval = 2
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let watchdog = DispatchWorkItem {
                    guard process.isRunning else { return }
                    process.terminate()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + killGrace) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
                // Returns at EOF, i.e. when the process exits or is killed.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()
                // A timed-out process ends with .uncaughtSignal, so it counts as failed.
                guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}
