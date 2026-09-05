import Foundation

@Observable
@MainActor
final class ProjectService {
    private(set) var projects: [ProjectStats] = []
    private(set) var isLoading = false

    private let modelCatalogService: ModelCatalogService?

    init(claudeDir: String = "~/.claude", modelCatalogService: ModelCatalogService? = nil) {
        self.modelCatalogService = modelCatalogService
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
            let dirs = JSONLLocator.allProjectsDirectories()
            let result = ProjectService.scanWithModels(dirs: dirs)
            await MainActor.run { [weak self] in
                self?.projects = result.projects
                self?.modelCatalogService?.noteModels(result.models)
                self?.isLoading = false
            }
        }
    }

    // MARK: - Scanning

    /// Scans all project subdirs across every supplied projects directory.
    /// Returns ProjectStats grouped by `cwd`, sorted by estimated cost descending.
    nonisolated static func scanAllProjects(dirs: [String]) -> [ProjectStats] {
        scanWithModels(dirs: dirs).projects
    }

    nonisolated static func scanWithModels(dirs: [String]) -> (projects: [ProjectStats], models: Set<String>) {
        var models = Set<String>()
        let fm = FileManager.default

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
            var anonymousMessageCount = 0
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

                // sessions-index.json has no token usage, so JSONL remains authoritative.
                for filePath in JSONLLocator.files(inProjectDirectory: subdirPath) {
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

                        // Unique message dedup via message.id. Lines without an ID are
                        // independent messages and remain counted individually.
                        let shouldCountUsage: Bool
                        if let message = obj["message"] as? [String: Any],
                           let msgId = message["id"] as? String,
                           !msgId.isEmpty {
                            shouldCountUsage = accum.messageIds.insert(msgId).inserted
                        } else {
                            accum.anonymousMessageCount += 1
                            shouldCountUsage = true
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
                            if shouldCountUsage, let idx = sparklineDays.firstIndex(of: dayStart) {
                                accum.dailyCounts[idx] += 1
                            }
                        }

                        if let message = obj["message"] as? [String: Any], let model = message["model"] as? String {
                            models.insert(model)
                        }

                        // Cost from token usage
                        if shouldCountUsage,
                           let message = obj["message"] as? [String: Any],
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
                totalMessages: accum.messageIds.count + accum.anonymousMessageCount,
                branches: accum.branches,
                lastActive: accum.lastActive,
                estimatedCost: accum.estimatedCost,
                dailyMessageCounts: accum.dailyCounts
            ))
        }

        result.sort()
        return (result, models)
    }
}
