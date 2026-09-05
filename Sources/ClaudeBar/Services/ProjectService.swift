import Foundation

@Observable
@MainActor
final class ProjectService {
    private(set) var projects: [ProjectStats] = []
    private(set) var isLoading = false

    /// Kept for backward compatibility; internally we now discover all ~/.claude* dirs.
    private let claudeDir: String

    init(claudeDir: String = "~/.claude") {
        self.claudeDir = claudeDir
        reload()
    }

    var totalProjects: Int { projects.count }

    /// Reload projects from all ~/.claude*/projects/ directories.
    /// The `totalCostEstimate` parameter is kept for backward compatibility but is
    /// no longer used — costs are now computed directly from JSONL token data.
    func reload(totalCostEstimate: Double = 0) {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .utility) { [weak self] in
            let dirs = ProjectService.allProjectsDirs()
            let result = ProjectService.scanAllProjects(dirs: dirs)
            await MainActor.run { [weak self] in
                self?.projects = result
                self?.isLoading = false
            }
        }
    }

    // MARK: - Multi-installation discovery

    /// Returns all ~/.claude*/projects/ paths that actually exist as directories.
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

    // MARK: - Scanning

    /// Scans all project subdirs across every supplied projects directory.
    /// Returns ProjectStats grouped by `cwd`, sorted by estimated cost descending.
    private nonisolated static func scanAllProjects(dirs: [String]) -> [ProjectStats] {
        let fm = FileManager.default
        let decoder = JSONDecoder()

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sparklineDays: [Date] = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -(6 - offset), to: today)
        }

        // Accumulated stats per projectPath (cwd)
        struct Accum {
            var sessionCount = 0
            var messageIds = Set<String>()
            var branches = Set<String>()
            var lastActive: Date? = nil
            var estimatedCost: Double = 0
            var dailyCounts = [Int](repeating: 0, count: 7)
        }
        var grouped: [String: Accum] = [:]

        for projectsDir in dirs {
            guard let subdirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { continue }

            for subdirName in subdirs {
                let subdirPath = projectsDir + "/" + subdirName

                // Fast path: try sessions-index.json for forward compatibility
                let indexPath = subdirPath + "/sessions-index.json"
                if let data = try? Data(contentsOf: URL(fileURLWithPath: indexPath)),
                   let index = try? decoder.decode(SessionIndex.self, from: data) {
                    for entry in index.entries {
                        let key = entry.projectPath
                        var accum = grouped[key] ?? Accum()
                        accum.sessionCount += 1
                        if let count = entry.messageCount {
                            // No real message IDs from index — use synthetic ones to avoid
                            // collision across sessions from different dirs.
                            for i in 0..<count {
                                accum.messageIds.insert(entry.sessionId + "-\(i)")
                            }
                        }
                        if let branch = entry.gitBranch, !branch.isEmpty {
                            accum.branches.insert(branch)
                        }
                        if let modStr = entry.modified,
                           let date = isoFull.date(from: modStr) ?? isoBasic.date(from: modStr) {
                            if let current = accum.lastActive {
                                if date > current { accum.lastActive = date }
                            } else {
                                accum.lastActive = date
                            }
                            // Sparkline: bucket by modified date
                            let dayStart = calendar.startOfDay(for: date)
                            if let idx = sparklineDays.firstIndex(of: dayStart) {
                                accum.dailyCounts[idx] += entry.messageCount ?? 1
                            }
                        }
                        grouped[key] = accum
                    }
                    continue // index loaded — skip JSONL scan for this subdir
                }

                // Fallback: scan JSONL files directly
                guard let files = try? fm.contentsOfDirectory(atPath: subdirPath) else { continue }
                let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") }

                for filename in jsonlFiles {
                    let filePath = subdirPath + "/" + filename
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { continue }
                    let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)

                    var sessionProjectPath: String? = nil
                    var sessionCount = 0

                    for lineData in lines {
                        guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

                        // Only process assistant messages
                        guard let type = obj["type"] as? String, type == "assistant" else { continue }

                        // Determine project path from the first valid cwd we encounter
                        if sessionProjectPath == nil, let cwd = obj["cwd"] as? String, !cwd.isEmpty {
                            sessionProjectPath = cwd
                        }
                        let key = sessionProjectPath ?? subdirName

                        var accum = grouped[key] ?? Accum()

                        // Unique message dedup via message.id
                        if let message = obj["message"] as? [String: Any],
                           let msgId = message["id"] as? String {
                            accum.messageIds.insert(msgId)
                        }

                        // Git branch
                        if let branch = obj["gitBranch"] as? String, !branch.isEmpty {
                            accum.branches.insert(branch)
                        }

                        // Timestamp → lastActive + sparkline
                        if let tsStr = obj["timestamp"] as? String,
                           let date = isoFull.date(from: tsStr) ?? isoBasic.date(from: tsStr) {
                            if let current = accum.lastActive {
                                if date > current { accum.lastActive = date }
                            } else {
                                accum.lastActive = date
                            }
                            let dayStart = calendar.startOfDay(for: date)
                            if let idx = sparklineDays.firstIndex(of: dayStart) {
                                accum.dailyCounts[idx] += 1
                            }
                        }

                        // Cost from token usage
                        if let message = obj["message"] as? [String: Any],
                           let model = message["model"] as? String,
                           let usage = message["usage"] as? [String: Any] {
                            let input      = (usage["input_tokens"] as? Int) ?? 0
                            let output     = (usage["output_tokens"] as? Int) ?? 0
                            let cacheRead  = (usage["cache_read_input_tokens"] as? Int) ?? 0
                            let cacheWrite = (usage["cache_creation_input_tokens"] as? Int) ?? 0
                            accum.estimatedCost += CostCalculator.cost(
                                modelId: model,
                                input: input,
                                output: output,
                                cacheRead: cacheRead,
                                cacheCreation: cacheWrite
                            )
                        }

                        grouped[key] = accum
                        sessionCount += 1
                    }

                    // Count this .jsonl file as exactly one session for the project.
                    // sessionCount > 0 means we found at least one assistant line.
                    if sessionCount > 0 {
                        let key = sessionProjectPath ?? subdirName
                        grouped[key, default: Accum()].sessionCount += 1
                    }
                }
            }
        }

        // Build ProjectStats from accumulated data
        var result: [ProjectStats] = []
        for (projectPath, accum) in grouped {
            let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
            result.append(ProjectStats(
                projectPath: projectPath,
                projectName: projectName,
                sessionCount: accum.sessionCount,
                totalMessages: accum.messageIds.count,
                branches: accum.branches,
                lastActive: accum.lastActive,
                estimatedCost: accum.estimatedCost,
                dailyMessageCounts: accum.dailyCounts
            ))
        }

        result.sort()
        return result
    }
}
