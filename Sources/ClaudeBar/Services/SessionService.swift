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

        let sorted = sessions.sorted { $0.startedAt > $1.startedAt }

        var estimates: [String: Double] = [:]
        for session in sorted {
            estimates[session.sessionId] = estimateContext(for: session)
        }
        contextEstimates = estimates
        activeSessions = sorted
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

    // MARK: - Context Estimation

    /// Estimates the context window usage for an active session (0.0 – 1.0).
    ///
    /// Reads the session's JSONL transcript and estimates tokens from file size.
    /// Rough heuristic: ~4 chars per token, JSON overhead ~2×, so tokens ≈ fileSize / 8.
    func estimateContext(for session: ActiveSession) -> Double {
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

    // MARK: - Provider Detection

    /// Detects configured AI providers from claude.json and stats.
    func detectProviders(statsService: StatsService) -> [ProviderInfo] {
        var providers: [ProviderInfo] = []

        // Claude is always present
        let claudeTotalTokens = statsService.stats?.modelUsage.values.reduce(0) {
            $0 + $1.inputTokens + $1.outputTokens
        }
        providers.append(ProviderInfo(
            name: "Claude",
            icon: "brain.head.profile",
            isConfigured: true,
            totalTokens: claudeTotalTokens,
            estimatedCost: statsService.totalCostEstimate,
            details: "Local stats from stats-cache.json"
        ))

        // Gemini — check if gemini-delegate MCP server is configured
        let claudeJsonPath = claudeDir.isEmpty
            ? NSString(string: "~/.claude.json").expandingTildeInPath
            : (claudeDir as NSString).deletingLastPathComponent + "/.claude.json"
        let geminiConfigured = isGeminiConfigured(claudeJsonPath: claudeJsonPath)
        providers.append(ProviderInfo(
            name: "Gemini",
            icon: "sparkles",
            isConfigured: geminiConfigured,
            totalTokens: nil,
            estimatedCost: nil,
            details: geminiConfigured
                ? "via gemini-delegate MCP (no local tracking)"
                : "Not configured"
        ))

        return providers
    }

    private func isGeminiConfigured(claudeJsonPath: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: claudeJsonPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = json["mcpServers"] as? [String: Any] else {
            return false
        }
        return mcpServers.keys.contains(where: { $0.lowercased().contains("gemini") })
    }

    // MARK: - Helpers

    private func isProcessRunning(pid: Int) -> Bool {
        kill(Int32(pid), 0) == 0
    }
}
