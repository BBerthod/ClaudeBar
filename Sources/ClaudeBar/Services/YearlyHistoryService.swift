import Foundation

@Observable
@MainActor
final class YearlyHistoryService {
    private(set) var dayStats: [Date: DayStats] = [:]
    private(set) var last30DaysActivity: [DailyActivity] = []
    private(set) var last30DaysTokens: [DailyModelTokens] = []
    private(set) var isLoading = false
    private(set) var isLoaded = false

    private let projectsDir: String

    init(claudeDir: String = "~/.claude") {
        // claudeDir param kept for backward compat but we auto-detect all dirs in scan.
        // Store it but don't use it — allProjectsDirs() finds all dirs automatically.
        self.projectsDir = NSString(string: claudeDir).expandingTildeInPath + "/projects"
    }

    func load() async {
        guard !isLoading && !isLoaded else { return }
        isLoading = true
        let dirs = Self.allProjectsDirs()
        let result = await Task.detached(priority: .utility) {
            YearlyHistoryService.scan(projectsDirs: dirs)
        }.value
        dayStats = result.dayStats
        last30DaysActivity = result.activity
        last30DaysTokens = result.tokens
        isLoading = false
        isLoaded = true
    }

    // MARK: - Directory discovery

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

    // MARK: - Background scan (nonisolated)

    private nonisolated static func scan(
        projectsDirs: [String]
    ) -> (dayStats: [Date: DayStats], activity: [DailyActivity], tokens: [DailyModelTokens]) {
        let fm = FileManager.default
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let cutoff365 = calendar.date(byAdding: .day, value: -364, to: today),
              let cutoff30  = calendar.date(byAdding: .day, value: -29,  to: today) else {
            return ([:], [], [])
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Accumulators for dayStats (365-day)
        var dayTokenMap: [Date: Int] = [:]
        var dayCostMap:  [Date: Double] = [:]

        // Accumulators for last-30-days activity
        var dayMessageCounts: [Date: Int] = [:]
        var dayToolCounts:    [Date: Int] = [:]
        var daySessionIds:    [Date: Set<String>] = [:]

        // Accumulators for last-30-days model tokens (input+output only per model)
        var dayModelTokenMap: [Date: [String: Int]] = [:]

        // Deduplication
        var seenMessages: Set<String> = []

        for projectsDir in projectsDirs {
            guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { continue }
            for dir in projectDirs {
                let dirPath = projectsDir + "/" + dir
                guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
                for file in files where file.hasSuffix(".jsonl") {
                    let path = dirPath + "/" + file
                    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                    for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        // Only process assistant messages
                        guard (json["type"] as? String) == "assistant" else { continue }

                        guard let tsStr = json["timestamp"] as? String,
                              let ts = isoFormatter.date(from: tsStr) else { continue }

                        let day = calendar.startOfDay(for: ts)
                        guard day >= cutoff365 else { continue }

                        let sessionId = json["sessionId"] as? String ?? ""
                        let messageObj = json["message"] as? [String: Any]
                        let msgId = messageObj?["id"] as? String ?? ""
                        let model = messageObj?["model"] as? String ?? ""
                        let usageObj = messageObj?["usage"] as? [String: Any]
                        let inputTokens  = usageObj?["input_tokens"]                  as? Int ?? 0
                        let outputTokens = usageObj?["output_tokens"]                 as? Int ?? 0
                        let cacheRead    = usageObj?["cache_read_input_tokens"]       as? Int ?? 0
                        let cacheWrite   = usageObj?["cache_creation_input_tokens"]   as? Int ?? 0
                        let totalTokens  = inputTokens + outputTokens + cacheRead + cacheWrite

                        // Deduplication key: same message on same day
                        let dayEpoch = Int(day.timeIntervalSince1970)
                        let msgKey = "\(dayEpoch):\(msgId)"
                        let isDuplicate = !msgId.isEmpty && seenMessages.contains(msgKey)
                        if !msgId.isEmpty {
                            seenMessages.insert(msgKey)
                        }

                        // ---- 365-day dayStats (not deduplicated for cost — follow original behaviour) ----
                        var cost = 0.0
                        if !model.isEmpty && totalTokens > 0 {
                            let p = CostCalculator.pricing(for: model)
                            let mTok = 1_000_000.0
                            cost = Double(inputTokens)  / mTok * p.inputPerMTok
                                 + Double(outputTokens) / mTok * p.outputPerMTok
                                 + Double(cacheRead)    / mTok * p.cacheReadPerMTok
                                 + Double(cacheWrite)   / mTok * p.cacheWritePerMTok
                        }
                        dayTokenMap[day, default: 0] += totalTokens
                        dayCostMap[day,  default: 0.0] += cost

                        // ---- 30-day activity & token data (deduplicated) ----
                        guard day >= cutoff30, !isDuplicate else { continue }

                        // Session count per day
                        if !sessionId.isEmpty {
                            daySessionIds[day, default: []].insert(sessionId)
                        }

                        // Message count
                        dayMessageCounts[day, default: 0] += 1

                        // Tool-use count from message.content
                        if let contentArray = messageObj?["content"] as? [[String: Any]] {
                            let toolCount = contentArray.filter { ($0["type"] as? String) == "tool_use" }.count
                            dayToolCounts[day, default: 0] += toolCount
                        }

                        // Model tokens (input + output only, matching DailyModelTokens convention)
                        if !model.isEmpty {
                            let io = inputTokens + outputTokens
                            dayModelTokenMap[day, default: [:]][model, default: 0] += io
                        }
                    }
                }
            }
        }

        // Build dayStats
        var resultDayStats: [Date: DayStats] = [:]
        for (day, tokens) in dayTokenMap {
            resultDayStats[day] = DayStats(tokens: tokens, cost: dayCostMap[day] ?? 0.0)
        }

        // Build last-30-days activity (sorted ascending)
        var activity: [DailyActivity] = []
        var cursor = cutoff30
        while cursor <= today {
            let dateStr = DateFormatter.isoDate.string(from: cursor)
            let msgCount  = dayMessageCounts[cursor] ?? 0
            let sessCount = daySessionIds[cursor]?.count ?? 0
            let toolCount = dayToolCounts[cursor] ?? 0
            activity.append(DailyActivity(
                date: dateStr,
                messageCount: msgCount,
                sessionCount: sessCount,
                toolCallCount: toolCount
            ))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
        }

        // Build last-30-days token data (sorted ascending)
        var tokens: [DailyModelTokens] = []
        cursor = cutoff30
        while cursor <= today {
            let dateStr = DateFormatter.isoDate.string(from: cursor)
            let byModel = dayModelTokenMap[cursor] ?? [:]
            tokens.append(DailyModelTokens(date: dateStr, tokensByModel: byModel))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
        }

        return (dayStats: resultDayStats, activity: activity, tokens: tokens)
    }
}
