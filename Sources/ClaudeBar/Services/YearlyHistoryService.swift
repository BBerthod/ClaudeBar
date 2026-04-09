import Foundation

@Observable
@MainActor
final class YearlyHistoryService {
    private(set) var dayStats: [Date: DayStats] = [:]
    private(set) var isLoading = false

    private let projectsDir: String

    init(claudeDir: String = "~/.claude") {
        self.projectsDir = (claudeDir as NSString).expandingTildeInPath + "/projects"
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        let dir = projectsDir
        let result = await Task.detached(priority: .utility) {
            YearlyHistoryService.scan(projectsDir: dir)
        }.value
        dayStats = result
        isLoading = false
    }

    // MARK: - Background scan (nonisolated)
    private nonisolated static func scan(projectsDir: String) -> [Date: DayStats] {
        let fm = FileManager.default
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -364, to: today) else { return [:] }

        var result: [Date: DayStats] = [:]
        let decoder = JSONDecoder()
        let isoFormatter = ISO8601DateFormatter()

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { return result }
        for dir in projectDirs {
            let dirPath = projectsDir + "/" + dir
            guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let path = dirPath + "/" + file
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                    guard let data = line.data(using: .utf8),
                          let entry = try? decoder.decode(RawEntry.self, from: data),
                          let tsStr = entry.timestamp,
                          let ts = isoFormatter.date(from: tsStr) else { continue }

                    let day = calendar.startOfDay(for: ts)
                    guard day >= cutoff else { continue }

                    let u = entry.usage
                    let inputTokens  = u?.input_tokens ?? 0
                    let outputTokens = u?.output_tokens ?? 0
                    let cacheRead    = u?.cache_read_input_tokens ?? 0
                    let cacheWrite   = u?.cache_creation_input_tokens ?? 0
                    let totalTokens  = inputTokens + outputTokens + cacheRead + cacheWrite

                    var cost = 0.0
                    if let model = entry.model, totalTokens > 0 {
                        let p = CostCalculator.pricing(for: model)
                        let mTok = 1_000_000.0
                        cost = Double(inputTokens)  / mTok * p.inputPerMTok
                             + Double(outputTokens) / mTok * p.outputPerMTok
                             + Double(cacheRead)    / mTok * p.cacheReadPerMTok
                             + Double(cacheWrite)   / mTok * p.cacheWritePerMTok
                    }

                    result[day, default: DayStats(tokens: 0, cost: 0)].tokens += totalTokens
                    result[day, default: DayStats(tokens: 0, cost: 0)].cost += cost
                }
            }
        }
        return result
    }

    // MARK: - Decode helpers

    private struct RawEntry: Decodable {
        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_read_input_tokens: Int?
            let cache_creation_input_tokens: Int?
        }
        let timestamp: String?
        let usage: Usage?
        let model: String?
    }
}
