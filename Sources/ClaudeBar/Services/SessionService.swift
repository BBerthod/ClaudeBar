import Foundation
import Darwin

@Observable
@MainActor
final class SessionService {
    private(set) var activeSessions: [ActiveSession] = []
    private(set) var recentSessions: [SessionIndexEntry] = []
    private var fileWatcher = FileWatcher()
    private var timer: Timer?

    private let sessionsDir: String
    private let projectsDir: String

    init(claudeDir: String = "~/.claude") {
        let base = NSString(string: claudeDir).expandingTildeInPath
        self.sessionsDir = base + "/sessions"
        self.projectsDir = base + "/projects"
        loadActiveSessions()
        loadRecentSessions()
        startPolling()
        startWatchingProjects()
    }

    // MARK: - Active Sessions

    private func loadActiveSessions() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else {
            activeSessions = []
            return
        }

        let decoder = JSONDecoder()
        var sessions: [ActiveSession] = []

        for filename in files {
            let filePath = sessionsDir + "/" + filename
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { continue }
            guard let session = try? decoder.decode(ActiveSession.self, from: data) else { continue }
            guard isProcessRunning(pid: session.pid) else { continue }
            sessions.append(session)
        }

        activeSessions = sessions.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Recent Sessions

    private func loadRecentSessions() {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else {
            recentSessions = []
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

        recentSessions = Array(allEntries.prefix(50))
    }

    // MARK: - Polling

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadActiveSessions()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - File Watching

    private func startWatchingProjects() {
        fileWatcher.watch(path: projectsDir) { [weak self] in
            self?.loadRecentSessions()
        }
    }

    // MARK: - Helpers

    private func isProcessRunning(pid: Int) -> Bool {
        kill(Int32(pid), 0) == 0
    }
}
