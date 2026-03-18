import Foundation

/// Computes today's stats by parsing JSONL session files directly.
///
/// Used as a fallback when `stats-cache.json` doesn't have an entry for today.
/// Deduplicates by `message.id` (Claude Code writes multiple streaming chunks
/// per API call with the same message ID — we keep the last one).
@Observable
@MainActor
final class LiveStatsService {
    private(set) var todayMessages: Int = 0
    private(set) var todayTokens: Int = 0
    private(set) var todayToolCalls: Int = 0
    private(set) var todayCost: Double = 0
    private(set) var tokensByModel: [(model: String, tokens: Int)] = []
    private(set) var isStale: Bool = false
    private(set) var lastParsed: Date?

    private let projectsDir: String
    private var knownMtimes: [String: TimeInterval] = [:]
    private var timer: Timer?

    init(claudeDir: String = "~/.claude") {
        self.projectsDir = NSString(string: claudeDir).expandingTildeInPath + "/projects"
    }

    /// Call once stats-cache is loaded to decide if live parsing is needed.
    func updateIfNeeded(statsService: StatsService) {
        let hasToday = statsService.todayMessages > 0 || statsService.todayTokens > 0
        isStale = !hasToday

        if isStale {
            parseToday()
            startPolling()
        } else {
            stopPolling()
        }
    }

    // MARK: - Parsing

    private func parseToday() {
        let fm = FileManager.default
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date()).timeIntervalSince1970

        // Collect JSONL files modified today
        var jsonlFiles: [String] = []

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { return }
        for dir in projectDirs {
            let dirPath = projectsDir + "/" + dir

            // Direct session files
            if let files = try? fm.contentsOfDirectory(atPath: dirPath) {
                for file in files where file.hasSuffix(".jsonl") {
                    let path = dirPath + "/" + file
                    if let mtime = modTime(path), mtime >= todayStart {
                        jsonlFiles.append(path)
                    }
                }
            }

            // Subagent files
            let subPath = dirPath + "/subagents"
            if let files = try? fm.contentsOfDirectory(atPath: subPath) {
                for file in files where file.hasSuffix(".jsonl") {
                    let path = subPath + "/" + file
                    if let mtime = modTime(path), mtime >= todayStart {
                        jsonlFiles.append(path)
                    }
                }
            }
        }

        // Parse all today's files, dedup by message ID
        var messagesByID: [String: (model: String, usage: [String: Any])] = [:]
        var toolCallCount = 0

        for path in jsonlFiles {
            autoreleasepool {
                guard let data = fm.contents(atPath: path),
                      let content = String(data: data, encoding: .utf8) else { return }

                for line in content.split(separator: "\n") {
                    guard let lineData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                        continue
                    }

                    let type = json["type"] as? String ?? ""

                    if type == "assistant", let message = json["message"] as? [String: Any] {
                        guard let usage = message["usage"] as? [String: Any] else { continue }
                        let msgID = message["id"] as? String ?? UUID().uuidString
                        let model = message["model"] as? String ?? "unknown"

                        // Skip synthetic messages
                        guard model != "<synthetic>" else { continue }

                        messagesByID[msgID] = (model: model, usage: usage)
                    }

                    // Count tool use
                    if type == "tool_use" || type == "tool_result" {
                        toolCallCount += 1
                    }
                }
            }
        }

        // Aggregate stats
        var totalTokens = 0
        var totalCost = 0.0
        var modelTokenCounts: [String: Int] = [:]

        for (_, entry) in messagesByID {
            let inp = entry.usage["input_tokens"] as? Int ?? 0
            let out = entry.usage["output_tokens"] as? Int ?? 0
            let cacheRead = entry.usage["cache_read_input_tokens"] as? Int ?? 0
            let cacheWrite = entry.usage["cache_creation_input_tokens"] as? Int ?? 0

            let msgTokens = inp + out + cacheRead + cacheWrite
            totalTokens += msgTokens
            modelTokenCounts[entry.model, default: 0] += msgTokens

            totalCost += Self.messageCost(
                model: entry.model,
                input: inp, output: out,
                cacheRead: cacheRead, cacheWrite: cacheWrite
            )
        }

        // Update published properties
        todayMessages = messagesByID.count
        todayTokens = totalTokens
        todayToolCalls = toolCallCount / 2  // tool_use + tool_result = 1 logical call
        todayCost = totalCost
        tokensByModel = modelTokenCounts
            .map { (model: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }
        lastParsed = Date()
    }

    // MARK: - Polling

    private func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.parseToday()
            }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Helpers

    private func modTime(_ path: String) -> TimeInterval? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else {
            return nil
        }
        return date.timeIntervalSince1970
    }

    /// Per-message cost calculation with model-specific pricing.
    private static func messageCost(
        model: String, input: Int, output: Int,
        cacheRead: Int, cacheWrite: Int
    ) -> Double {
        let mtok = 1_000_000.0
        let lower = model.lowercased()

        let (iRate, oRate, crRate, cwRate): (Double, Double, Double, Double)
        if lower.contains("opus") {
            (iRate, oRate, crRate, cwRate) = (15.0, 75.0, 1.5, 18.75)
        } else if lower.contains("sonnet") {
            (iRate, oRate, crRate, cwRate) = (3.0, 15.0, 0.3, 3.75)
        } else if lower.contains("haiku") {
            (iRate, oRate, crRate, cwRate) = (0.25, 1.25, 0.025, 0.3125)
        } else {
            (iRate, oRate, crRate, cwRate) = (15.0, 75.0, 1.5, 18.75) // conservative
        }

        return (Double(input) * iRate + Double(output) * oRate +
                Double(cacheRead) * crRate + Double(cacheWrite) * cwRate) / mtok
    }
}
