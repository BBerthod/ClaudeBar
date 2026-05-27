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
            let finalEstimates = estimates

            await MainActor.run {
                let previousCount = self.activeSessions.count
                self.contextEstimates = finalEstimates
                self.activeSessions = sorted
                if sorted.count != previousCount {
                    Log.sessions.info("Active sessions: \(sorted.count)")
                }
            }
        }
    }

    // MARK: - Recent Sessions

    private func loadRecentSessions() {
        let dirs = SessionService.allProjectsDirs()
        Task.detached(priority: .userInitiated) {
            let result = SessionService.scanRecentSessions(fromProjectsDirs: dirs, limit: 50)

            await MainActor.run {
                self.recentSessions = result
            }
        }
    }

    /// Builds the recent-sessions list directly from JSONL files, sorted by file mtime (newest first).
    nonisolated static func scanRecentSessions(fromProjectsDirs dirs: [String], limit: Int) -> [SessionIndexEntry] {
        let fm = FileManager.default
        var candidates: [(path: String, mtime: Date)] = []

        for projectsDir in dirs {
            guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { continue }

            for projectDir in projectDirs {
                let dirPath = projectsDir + "/" + projectDir
                guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }

                for file in files where file.hasSuffix(".jsonl") {
                    let path = dirPath + "/" + file
                    guard let attrs = try? fm.attributesOfItem(atPath: path),
                          let mtime = attrs[.modificationDate] as? Date else { continue }
                    candidates.append((path, mtime))
                }
            }
        }

        candidates.sort { $0.mtime > $1.mtime }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var entries: [SessionIndexEntry] = []
        for candidate in candidates.prefix(limit) {
            let sessionId = ((candidate.path as NSString).lastPathComponent as NSString).deletingPathExtension
            let head: String = {
                guard let handle = FileHandle(forReadingAtPath: candidate.path) else { return "" }
                defer { try? handle.close() }
                let data = (try? handle.read(upToCount: 65_536)) ?? Data()
                return String(decoding: data, as: UTF8.self)
            }()
            let lines = head.split(separator: "\n").map(String.init)
            let meta = sessionMetadata(fromLines: lines)

            entries.append(SessionIndexEntry(
                sessionId: sessionId,
                fullPath: candidate.path,
                fileMtime: Int(candidate.mtime.timeIntervalSince1970 * 1_000),
                firstPrompt: meta.summary,
                summary: meta.summary,
                messageCount: nil,
                created: nil,
                modified: iso.string(from: candidate.mtime),
                gitBranch: meta.gitBranch,
                projectPath: meta.cwd ?? dirNameToPath((candidate.path as NSString).deletingLastPathComponent),
                isSidechain: nil
            ))
        }

        return entries
    }

    /// Best-effort decode of an encoded project dir path into a display path (fallback only).
    nonisolated static func dirNameToPath(_ dirPath: String) -> String {
        let name = (dirPath as NSString).lastPathComponent
        if name.hasPrefix("-") {
            return "/" + name.dropFirst().replacingOccurrences(of: "-", with: "/")
        }
        return name
    }

    /// Pure: extracts cwd, gitBranch, and first user prompt (as summary) from JSONL lines.
    nonisolated static func sessionMetadata(fromLines lines: [String]) -> (cwd: String?, gitBranch: String?, summary: String?) {
        var cwd: String?
        var gitBranch: String?
        var summary: String?

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if cwd == nil, let value = json["cwd"] as? String {
                cwd = value
            }

            if gitBranch == nil, let value = json["gitBranch"] as? String, !value.isEmpty {
                gitBranch = value
            }

            if summary == nil,
               (json["type"] as? String) == "user",
               let message = json["message"] as? [String: Any] {
                if let value = message["content"] as? String {
                    summary = String(value.prefix(100))
                } else if let content = message["content"] as? [[String: Any]],
                          let textItem = content.first(where: { ($0["type"] as? String) == "text" }),
                          let value = textItem["text"] as? String {
                    summary = String(value.prefix(100))
                }
            }

            if cwd != nil && gitBranch != nil && summary != nil {
                break
            }
        }

        return (cwd, gitBranch, summary)
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
