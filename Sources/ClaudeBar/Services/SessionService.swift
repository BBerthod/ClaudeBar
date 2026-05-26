import Foundation
import Darwin
import os

@Observable
@MainActor
final class SessionService {
    private(set) var activeSessions: [ActiveSession] = []
    private(set) var recentSessions: [SessionIndexEntry] = []
    /// Context estimate for each active session (sessionId -> percentage 0.0-1.0)
    private(set) var contextEstimates: [String: Double] = [:]
    private var fileWatcher = FileWatcher()
    private var timer: Timer?

    private let sessionsDir: String
    private let projectsDir: String
    private let claudeDir: String

    init(claudeDir: String = "~/.claude") {
        let base = NSString(string: claudeDir).expandingTildeInPath
        self.claudeDir = base
        self.sessionsDir = base + "/sessions"
        self.projectsDir = base + "/projects"
        loadActiveSessions()
        loadRecentSessions()
        startPolling()
        startWatchingProjects()
    }

    // MARK: - Multi-installation discovery

    /// Returns all ~/.claude* directories that contain a `sessions/` subdirectory.
    private nonisolated static func allSessionsDirs() -> [String] {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: home)) ?? [])
            .filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .compactMap { name -> String? in
                let path = (home as NSString).appendingPathComponent(name) + "/sessions"
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue ? path : nil
            }
    }

    /// Returns all ~/.claude* directories that contain a `projects/` subdirectory.
    private nonisolated static func allProjectsDirs() -> [String] {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: home)) ?? [])
            .filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .compactMap { name -> String? in
                let path = (home as NSString).appendingPathComponent(name) + "/projects"
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue ? path : nil
            }
    }

    // MARK: - Active Sessions

    private func loadActiveSessions() {
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let decoder = JSONDecoder()
            var sessions: [ActiveSession] = []
            var estimates: [String: Double] = [:]

            for sessionsDir in SessionService.allSessionsDirs() {
                guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else { continue }
                let projectsDir = sessionsDir.replacingOccurrences(of: "/sessions", with: "/projects")

                for filename in files {
                    let filePath = sessionsDir + "/" + filename
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { continue }
                    guard let session = try? decoder.decode(ActiveSession.self, from: data) else { continue }
                    guard kill(Int32(session.pid), 0) == 0 else { continue }
                    sessions.append(session)
                    estimates[session.sessionId] = SessionService.estimateContext(for: session, projectsDir: projectsDir)
                }
            }

            let sorted = sessions.sorted { $0.startedAt > $1.startedAt }

            await MainActor.run {
                let previousCount = self.activeSessions.count
                self.contextEstimates = estimates
                self.activeSessions = sorted
                if sorted.count != previousCount {
                    Log.sessions.info("Active sessions: \(sorted.count)")
                }
            }
        }
    }

    // MARK: - Recent Sessions

    private func loadRecentSessions() {
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let decoder = JSONDecoder()
            var allEntries: [SessionIndexEntry] = []

            for projectsDir in SessionService.allProjectsDirs() {
                guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { continue }

                for projectDir in projectDirs {
                    let indexPath = projectsDir + "/" + projectDir + "/sessions-index.json"
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: indexPath)) else { continue }
                    guard let index = try? decoder.decode(SessionIndex.self, from: data) else { continue }
                    allEntries.append(contentsOf: index.entries)
                }
            }

            // Sort by modified date descending, then take the most recent 50
            allEntries.sort { lhs, rhs in
                // Treat nil modified as oldest possible
                guard let lhsMod = lhs.modified else { return false }
                guard let rhsMod = rhs.modified else { return true }
                return lhsMod > rhsMod
            }

            let result = Array(allEntries.prefix(50))

            await MainActor.run {
                self.recentSessions = result
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadActiveSessions()
            }
        }
    }

    // MARK: - File Watching

    private func startWatchingProjects() {
        fileWatcher.watch(path: projectsDir) { [weak self] in
            self?.loadRecentSessions()
        }
    }

    // MARK: - Context Estimation

    /// Context window (tokens) for a model name. Current Claude 4 models support 1M; others default 200K.
    nonisolated static func contextWindow(forModel model: String) -> Int {
        if model.contains("opus-4") || model.contains("sonnet-4") { return 1_000_000 }
        return 200_000
    }

    /// Pure: given JSONL lines, returns context-window fraction (0.0–1.0) from the LAST
    /// assistant message's usage (input + cache_read + cache_creation), divided by the model window.
    nonisolated static func contextFraction(fromLines lines: [String]) -> Double {
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["type"] as? String) == "assistant",
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }

            let input = (usage["input_tokens"] as? Int) ?? 0
            let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
            let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
            let contextTokens = input + cacheRead + cacheCreate
            guard contextTokens > 0 else { continue }

            let model = (message["model"] as? String) ?? ""
            return min(Double(contextTokens) / Double(contextWindow(forModel: model)), 1.0)
        }
        return 0
    }

    /// Estimates context-window usage (0.0–1.0) for an active session by reading the tail of its
    /// JSONL transcript and parsing the last assistant message's token usage.
    nonisolated static func estimateContext(for session: ActiveSession, projectsDir: String) -> Double {
        let encodedCwd = session.cwd.replacingOccurrences(of: "/", with: "-")
        let jsonlPath = projectsDir + "/" + encodedCwd + "/" + session.sessionId + ".jsonl"

        guard let handle = FileHandle(forReadingAtPath: jsonlPath) else { return 0 }
        defer { try? handle.close() }

        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: jsonlPath),
              let fileSize = attrs[.size] as? UInt64 else { return 0 }

        // Read only the last ~1MB; the last assistant message lives near the end.
        let tailSize: UInt64 = 1_000_000
        let offset = fileSize > tailSize ? fileSize - tailSize : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return 0 }

        // The first line may be partial when the tail starts mid-record.
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        return contextFraction(fromLines: lines)
    }

    /// Instance wrapper preserving the original public interface.
    func estimateContext(for session: ActiveSession) -> Double {
        SessionService.estimateContext(for: session, projectsDir: projectsDir)
    }
}
