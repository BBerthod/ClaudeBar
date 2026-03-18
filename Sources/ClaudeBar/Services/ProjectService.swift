import Foundation

@Observable
@MainActor
final class ProjectService {
    private(set) var projects: [ProjectStats] = []

    private let projectsDir: String

    init(claudeDir: String = "~/.claude") {
        self.projectsDir = NSString(string: claudeDir).expandingTildeInPath + "/projects"
        loadProjects()
    }

    var totalProjects: Int { projects.count }

    /// Called when stats update so cost estimates can be refreshed.
    func reload(totalCostEstimate: Double) {
        loadProjects(totalCostEstimate: totalCostEstimate)
    }

    // MARK: - Private

    private func loadProjects(totalCostEstimate: Double = 0) {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else {
            projects = []
            return
        }

        let decoder = JSONDecoder()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Fallback formatter without fractional seconds
        let isoFormatterBasic = ISO8601DateFormatter()
        isoFormatterBasic.formatOptions = [.withInternetDateTime]

        // Accumulate entries grouped by projectPath
        var grouped: [String: [SessionIndexEntry]] = [:]

        for dirName in projectDirs {
            let indexPath = projectsDir + "/" + dirName + "/sessions-index.json"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: indexPath)) else { continue }
            guard let index = try? decoder.decode(SessionIndex.self, from: data) else { continue }

            for entry in index.entries {
                let key = entry.projectPath
                grouped[key, default: []].append(entry)
            }
        }

        // Total messages across all projects (for cost ratio)
        let grandTotalMessages = grouped.values.reduce(0) { sum, entries in
            sum + entries.reduce(0) { $0 + ($1.messageCount ?? 0) }
        }

        // Build ProjectStats per projectPath
        var result: [ProjectStats] = []

        for (projectPath, entries) in grouped {
            let projectName = URL(fileURLWithPath: projectPath).lastPathComponent

            let sessionCount = entries.count
            let totalMessages = entries.reduce(0) { $0 + ($1.messageCount ?? 0) }

            var branches = Set<String>()
            for entry in entries {
                if let branch = entry.gitBranch, !branch.isEmpty {
                    branches.insert(branch)
                }
            }

            // Determine lastActive from the most recent modified date
            var lastActive: Date?
            for entry in entries {
                guard let modStr = entry.modified else { continue }
                let date = isoFormatter.date(from: modStr) ?? isoFormatterBasic.date(from: modStr)
                if let date {
                    if let current = lastActive {
                        if date > current { lastActive = date }
                    } else {
                        lastActive = date
                    }
                }
            }

            // Estimate cost proportional to message count
            let estimatedCost: Double
            if grandTotalMessages > 0 {
                estimatedCost = (Double(totalMessages) / Double(grandTotalMessages)) * totalCostEstimate
            } else {
                estimatedCost = 0
            }

            result.append(ProjectStats(
                projectPath: projectPath,
                projectName: projectName,
                sessionCount: sessionCount,
                totalMessages: totalMessages,
                branches: branches,
                lastActive: lastActive,
                estimatedCost: estimatedCost
            ))
        }

        result.sort()
        projects = result
    }
}
