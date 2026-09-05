import Foundation
import Observation

@Observable
@MainActor
final class GeminiActivityService {
    private(set) var isInstalled = false
    private(set) var activity = GeminiActivity()
    private(set) var lastError: String?

    private let cliDirectory: URL
    private let now: () -> Date
    private let disablePolling: Bool
    private let watcher = FileWatcher()
    private nonisolated let refreshTimer = ServiceTimer()
    private var isRefreshing = false

    init(
        cliDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/antigravity-cli"),
        now: @escaping () -> Date = Date.init,
        disablePolling: Bool = false
    ) {
        self.cliDirectory = cliDirectory
        self.now = now
        self.disablePolling = disablePolling
        var isDirectory: ObjCBool = false
        isInstalled = FileManager.default.fileExists(atPath: cliDirectory.path, isDirectory: &isDirectory) && isDirectory.boolValue
        if !disablePolling {
            Task { [weak self] in await self?.refresh() }
            refreshTimer.timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
            }
        }
    }

    deinit {
        refreshTimer.invalidate()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            if !disablePolling {
                let history = cliDirectory.appendingPathComponent("history.jsonl")
                let path = FileManager.default.fileExists(atPath: history.path) ? history.path : cliDirectory.path
                // Reattach after atomic replacement; watch the directory until history exists.
                watcher.watch(path: path) { [weak self] in
                    Task { @MainActor [weak self] in await self?.refresh() }
                }
            }
        }
        let directory = cliDirectory
        let startOfDay = Calendar.current.startOfDay(for: now())
        let result = await Task.detached(priority: .utility) {
            Self.readActivity(directory: directory, startOfDay: startOfDay)
        }.value
        isInstalled = result.installed
        lastError = result.error
        if let value = result.activity { activity = value }
    }

    private nonisolated static func readActivity(
        directory: URL, startOfDay: Date
    ) -> (installed: Bool, activity: GeminiActivity?, error: String?) {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return (false, GeminiActivity(), nil)
        }
        do {
            let database = directory.appendingPathComponent("conversation_summaries.db")
            let rows = fm.fileExists(atPath: database.path) ? try querySummaries(at: database) : []
            var activity = GeminiActivityParser.parseSummaries(tsvRows: rows, startOfDay: startOfDay)
            let history = directory.appendingPathComponent("history.jsonl")
            let lines = fm.fileExists(atPath: history.path) ? try readHistory(at: history) : []
            let parsed = GeminiActivityParser.parseHistory(lines: lines, startOfDay: startOfDay)
            activity.promptsToday = parsed.promptsToday
            activity.lastPromptAt = parsed.lastPromptAt
            // Only stat the token: never open or decode its contents.
            let token = directory.appendingPathComponent("antigravity-oauth-token")
            if let attributes = try? fm.attributesOfItem(atPath: token.path) {
                activity.isLoggedIn = attributes[.type] as? FileAttributeType == .typeRegular
                    && (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0
            }
            return (true, activity, nil)
        } catch {
            return (true, nil, error.localizedDescription)
        }
    }

    private struct SQLiteError: LocalizedError {
        let code: Int32
        var errorDescription: String? { "sqlite3 exited \(code)" }
    }

    private nonisolated static func querySummaries(at database: URL) throws -> [String] {
        let query = """
        SELECT conversation_id, last_user_input_time, last_modified_time, not_fully_idle, killed, agent_name, workspace_uris
        FROM conversation_summaries;
        """
        // URL encoding preserves literal ?, # and spaces in the database path.
        var uri = URLComponents(url: database, resolvingAgainstBaseURL: false)!
        uri.queryItems = [URLQueryItem(name: "mode", value: "ro"), URLQueryItem(name: "immutable", value: "1")]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-separator", "\t", uri.string!, query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
        defer { timeout.cancel() }
        // Drain while running so output larger than the pipe buffer cannot deadlock.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SQLiteError(code: process.terminationStatus) }
        return String(decoding: data, as: UTF8.self).components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private nonisolated static func readHistory(at url: URL) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let truncated = size > 5 * 1024 * 1024
        try handle.seek(toOffset: truncated ? size - 1024 * 1024 : 0)
        let data = try handle.readToEnd() ?? Data()
        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        // The tail can start inside a JSON record (or a UTF-8 sequence).
        if truncated, !lines.isEmpty { lines.removeFirst() }
        return lines
    }
}
