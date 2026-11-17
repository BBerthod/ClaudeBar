import Foundation

/// Per-transcript contributions kept in memory between refreshes, so a periodic refresh
/// only reads the transcripts whose size or modification date changed.
struct YearlyHistoryCache: Sendable {
    fileprivate var files: [String: YearlyFileContribution] = [:]
    fileprivate var timeZone: TimeZone?
    /// Transcripts actually opened by the last scan that used this cache.
    fileprivate(set) var lastReadPaths: [String] = []
}

/// One assistant line that can count: anonymous, or the first line of its key in its file.
fileprivate struct YearlyMessage: Sendable {
    let day: Date
    let messageId: String
    let sessionId: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheRead: Int
    let cacheWrite: Int
    /// nil when message.content is not an array (nothing added to the tool count).
    let toolCount: Int?
}

/// Deduplication key: same message on same day. Equivalent to the "\(dayEpoch):\(msgId)" string.
fileprivate struct YearlyMessageKey: Hashable {
    let dayEpoch: Int
    let messageId: String
}

fileprivate struct YearlyFileContribution: Sendable {
    let size: Int
    let modificationDate: Date
    /// Lines older than this day were dropped when the file was read.
    let cutoff365: Date
    /// Countable lines, in file order. Later lines repeating a key already seen in this file are dropped:
    /// the full scan always skips them.
    let messages: [YearlyMessage]
    /// Models of every line in the window, duplicates included, as the full scan collects them.
    let modelsByDay: [Date: Set<String>]
}

@Observable
@MainActor
final class YearlyHistoryService {
    private(set) var dayStats: [Date: DayStats] = [:]
    private(set) var last30DaysActivity: [DailyActivity] = []
    private(set) var last30DaysTokens: [DailyModelTokens] = []
    private(set) var last30DaysModelBreakdown: [String: ModelTokenBreakdown] = [:]
    private(set) var isLoading = false
    private(set) var isLoaded = false

    /// Sum of the estimated daily costs over the loaded window (JSONL-derived).
    var totalCost: Double { dayStats.values.reduce(0) { $0 + $1.cost } }

    /// Number of days with recorded token usage in the loaded window.
    var trackedDays: Int { dayStats.values.filter { $0.tokens > 0 }.count }

    private let projectsDir: String

    private let modelCatalogService: ModelCatalogService?

    @ObservationIgnored private var cache = YearlyHistoryCache()

    init(claudeDir: String = "~/.claude", modelCatalogService: ModelCatalogService? = nil) {
        self.modelCatalogService = modelCatalogService
        // claudeDir param kept for backward compat but we auto-detect all dirs in scan.
        // Store it but don't use it — allProjectsDirs() finds all dirs automatically.
        self.projectsDir = NSString(string: claudeDir).expandingTildeInPath + "/projects"
    }

    /// Loads history once (no-op if already loaded). Used for lazy first access.
    func load() async {
        guard !isLoaded else { return }
        await refresh()
    }

    /// Re-scans all projects dirs and updates the published stats.
    /// Safe to call periodically; guards against overlapping scans.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        let dirs = JSONLLocator.allProjectsDirectories()
        let previousCache = cache
        let (result, updatedCache) = await Task.detached(priority: .utility) {
            var cache = previousCache
            let result = YearlyHistoryService.scanWithModels(projectsDirs: dirs, cache: &cache)
            return (result, cache)
        }.value
        cache = updatedCache
        modelCatalogService?.noteModels(result.models)
        dayStats = result.dayStats
        last30DaysActivity = result.activity
        last30DaysTokens = result.tokens
        last30DaysModelBreakdown = result.modelBreakdown
        isLoading = false
        isLoaded = true
    }

    // MARK: - Background scan (nonisolated)

    nonisolated static func scan(
        projectsDirs: [String]
    ) -> (dayStats: [Date: DayStats], activity: [DailyActivity], tokens: [DailyModelTokens], modelBreakdown: [String: ModelTokenBreakdown]) {
        let result = scanWithModels(projectsDirs: projectsDirs)
        return (result.dayStats, result.activity, result.tokens, result.modelBreakdown)
    }

    nonisolated static func scanWithModels(
        projectsDirs: [String]
    ) -> (dayStats: [Date: DayStats], activity: [DailyActivity], tokens: [DailyModelTokens], modelBreakdown: [String: ModelTokenBreakdown], models: Set<String>) {
        var cache = YearlyHistoryCache()
        return scanWithModels(projectsDirs: projectsDirs, cache: &cache)
    }

    nonisolated static func scanWithModels(
        projectsDirs: [String],
        cache: inout YearlyHistoryCache
    ) -> (dayStats: [Date: DayStats], activity: [DailyActivity], tokens: [DailyModelTokens], modelBreakdown: [String: ModelTokenBreakdown], models: Set<String>) {
        cache.lastReadPaths = []
        ScanProfiler.mark("Yearly.scan", "begin")
        defer { ScanProfiler.mark("Yearly.scan", "end") }
        var models = Set<String>()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let cutoff365 = calendar.date(byAdding: .day, value: -364, to: today),
              let cutoff30  = calendar.date(byAdding: .day, value: -29,  to: today) else {
            return ([:], [], [], [:], [])
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
        var model30dBreakdown: [String: ModelTokenBreakdown] = [:]

        // Deduplication
        var seenMessages: Set<YearlyMessageKey> = []

        // Cached days were bucketed with the previous time zone.
        if cache.timeZone != calendar.timeZone {
            cache.files = [:]
            cache.timeZone = calendar.timeZone
        }

        // Refresh the per-file contributions: only new or changed transcripts are read.
        let fm = FileManager.default
        let paths = JSONLLocator.files(inProjectsDirectories: projectsDirs)
        var files: [String: YearlyFileContribution] = [:]
        for path in paths {
            // Stat before reading: a write landing during the read changes size or date for the next refresh.
            guard let attributes = try? fm.attributesOfItem(atPath: path),
                  let size = (attributes[.size] as? NSNumber)?.intValue,
                  let modificationDate = attributes[.modificationDate] as? Date
            else { continue }
            // Lines are appended with their own timestamp, so none is later than the file's
            // modification date: a file last modified before the window has no line inside it.
            guard modificationDate >= cutoff365 else { continue }
            if let cached = cache.files[path],
               cached.size == size,
               cached.modificationDate == modificationDate,
               cached.cutoff365 <= cutoff365 {
                files[path] = cached
                continue
            }
            guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { continue }
            ScanProfiler.recordFile(label: "Yearly.scan", path: path, bytes: fileData.count)
            cache.lastReadPaths.append(path)
            files[path] = readContribution(
                of: fileData,
                size: size,
                modificationDate: modificationDate,
                cutoff365: cutoff365,
                calendar: calendar,
                isoFormatter: isoFormatter
            )
        }
        // Deleted transcripts, and those now older than the window, drop out here.
        cache.files = files

        // Replays the countable lines in the full scan's order (sorted files, then file order),
        // so the first file holding a key wins and sums are added in the same order.
        for path in paths {
            guard let contribution = files[path] else { continue }
            for (day, dayModels) in contribution.modelsByDay where day >= cutoff365 {
                models.formUnion(dayModels)
            }
            for message in contribution.messages {
                let day = message.day
                guard day >= cutoff365 else { continue }

                if !message.messageId.isEmpty {
                    let msgKey = YearlyMessageKey(dayEpoch: Int(day.timeIntervalSince1970), messageId: message.messageId)
                    guard seenMessages.insert(msgKey).inserted else { continue }
                }

                let model = message.model
                let inputTokens  = message.inputTokens
                let outputTokens = message.outputTokens
                let cacheRead    = message.cacheRead
                let cacheWrite   = message.cacheWrite
                let totalTokens  = inputTokens + outputTokens + cacheRead + cacheWrite

                // ---- 365-day dayStats ----
                var cost = 0.0
                if !model.isEmpty && totalTokens > 0 {
                    cost = CostCalculator.cost(
                        modelId: model,
                        input: inputTokens,
                        output: outputTokens,
                        cacheRead: cacheRead,
                        cacheCreation: cacheWrite
                    )
                }
                dayTokenMap[day, default: 0] += totalTokens
                dayCostMap[day,  default: 0.0] += cost

                // ---- 30-day activity & token data (deduplicated) ----
                guard day >= cutoff30 else { continue }

                // Session count per day
                if !message.sessionId.isEmpty {
                    daySessionIds[day, default: []].insert(message.sessionId)
                }

                // Message count
                dayMessageCounts[day, default: 0] += 1

                // Tool-use count from message.content
                if let toolCount = message.toolCount {
                    dayToolCounts[day, default: 0] += toolCount
                }

                // Model tokens (input + output only, matching DailyModelTokens convention)
                if !model.isEmpty {
                    let io = inputTokens + outputTokens
                    dayModelTokenMap[day, default: [:]][model, default: 0] += io
                    model30dBreakdown[model, default: ModelTokenBreakdown()].input += inputTokens
                    model30dBreakdown[model, default: ModelTokenBreakdown()].output += outputTokens
                    model30dBreakdown[model, default: ModelTokenBreakdown()].cacheRead += cacheRead
                    model30dBreakdown[model, default: ModelTokenBreakdown()].cacheCreation += cacheWrite
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

        return (
            dayStats: resultDayStats,
            activity: activity,
            tokens: tokens,
            modelBreakdown: model30dBreakdown,
            models: models
        )
    }

    /// Parses one transcript into its countable lines, independently of every other file.
    private nonisolated static func readContribution(
        of fileData: Data,
        size: Int,
        modificationDate: Date,
        cutoff365: Date,
        calendar: Calendar,
        isoFormatter: ISO8601DateFormatter
    ) -> YearlyFileContribution {
        var messages: [YearlyMessage] = []
        var modelsByDay: [Date: Set<String>] = [:]
        var seenInFile: Set<YearlyMessageKey> = []
        // Session and model ids repeat on every line: keep one copy per file.
        var interned: [String: String] = [:]
        func intern(_ value: String) -> String {
            if let existing = interned[value] { return existing }
            interned[value] = value
            return value
        }

        for data in JSONLLines.lines(in: fileData, containing: "\"assistant\"") {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // Only process assistant messages
            guard (json["type"] as? String) == "assistant" else { continue }

            guard let tsStr = json["timestamp"] as? String,
                  let ts = isoFormatter.date(from: tsStr) else { continue }

            let day = calendar.startOfDay(for: ts)
            guard day >= cutoff365 else { continue }

            let messageObj = json["message"] as? [String: Any]
            let msgId = messageObj?["id"] as? String ?? ""
            let model = messageObj?["model"] as? String ?? ""
            modelsByDay[day, default: []].insert(model)

            // A repeat of a key already seen in this file is a duplicate whatever the other files hold.
            if !msgId.isEmpty {
                let msgKey = YearlyMessageKey(dayEpoch: Int(day.timeIntervalSince1970), messageId: msgId)
                guard seenInFile.insert(msgKey).inserted else { continue }
            }

            let usageObj = messageObj?["usage"] as? [String: Any]
            let toolCount = (messageObj?["content"] as? [[String: Any]])
                .map { content in content.filter { ($0["type"] as? String) == "tool_use" }.count }
            messages.append(YearlyMessage(
                day: day,
                messageId: msgId,
                sessionId: intern(json["sessionId"] as? String ?? ""),
                model: intern(model),
                inputTokens:  usageObj?["input_tokens"]                as? Int ?? 0,
                outputTokens: usageObj?["output_tokens"]               as? Int ?? 0,
                cacheRead:    usageObj?["cache_read_input_tokens"]     as? Int ?? 0,
                cacheWrite:   usageObj?["cache_creation_input_tokens"] as? Int ?? 0,
                toolCount: toolCount
            ))
        }

        return YearlyFileContribution(
            size: size,
            modificationDate: modificationDate,
            cutoff365: cutoff365,
            messages: messages,
            modelsByDay: modelsByDay
        )
    }
}
