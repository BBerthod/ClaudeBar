import Foundation
import Darwin

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

    // MARK: - Active Sessions

    private func loadActiveSessions() {
        let sessionsDir = self.sessionsDir
        let projectsDir = self.projectsDir

        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else {
                await MainActor.run {
                    self.activeSessions = []
                    self.contextEstimates = [:]
                }
                return
            }

            let decoder = JSONDecoder()
            var sessions: [ActiveSession] = []

            for filename in files {
                let filePath = sessionsDir + "/" + filename
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { continue }
                guard let session = try? decoder.decode(ActiveSession.self, from: data) else { continue }
                guard kill(Int32(session.pid), 0) == 0 else { continue }
                sessions.append(session)
            }

            let sorted = sessions.sorted { $0.startedAt > $1.startedAt }

            let estimates = Dictionary(
                uniqueKeysWithValues: sorted.map { session in
                    (session.sessionId, SessionService.estimateContext(for: session, projectsDir: projectsDir))
                }
            )

            await MainActor.run {
                self.contextEstimates = estimates
                self.activeSessions = sorted
            }
        }
    }

    // MARK: - Recent Sessions

    private func loadRecentSessions() {
        let projectsDir = self.projectsDir

        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else {
                await MainActor.run {
                    self.recentSessions = []
                }
                return
            }

            let decoder = JSONDecoder()
            var allEntries: [SessionIndexEntry] = []

            for projectDir in projectDirs {
                let indexPath = projectsDir + "/" + projectDir + "/sessions-index.json"
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: indexPath)) else { continue }
                guard let index = try? decoder.decode(SessionIndex.self, from: data) else { continue }
                allEntries.append(contentsOf: index.entries)
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

    /// Estimates the context window usage for an active session (0.0 – 1.0).
    ///
    /// Reads the session's JSONL transcript and estimates tokens from file size.
    /// Rough heuristic: ~4 chars per token, JSON overhead ~2×, so tokens ≈ fileSize / 8.
    ///
    /// The `projectsDir` parameter allows this method to be called from off-actor
    /// contexts (e.g. detached tasks) without capturing `self`.
    nonisolated static func estimateContext(for session: ActiveSession, projectsDir: String) -> Double {
        // ~/.claude/projects/{encoded-cwd}/{sessionId}.jsonl
        let encodedCwd = session.cwd.replacingOccurrences(of: "/", with: "-")
        let jsonlPath = projectsDir + "/" + encodedCwd + "/" + session.sessionId + ".jsonl"

        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: jsonlPath),
              let fileSize = attrs[.size] as? UInt64 else {
            return 0
        }

        // ~4 chars per token, JSON overhead ~2× raw text → effective tokens ≈ fileSize / 8
        let estimatedTokens = Double(fileSize) / 8.0

        // Default context window is 200K tokens
        let contextWindow: Double = 200_000

        return min(estimatedTokens / contextWindow, 1.0)
    }

    /// Instance wrapper preserving the original public interface.
    func estimateContext(for session: ActiveSession) -> Double {
        SessionService.estimateContext(for: session, projectsDir: projectsDir)
    }
}
