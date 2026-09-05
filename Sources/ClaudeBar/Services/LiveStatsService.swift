import Foundation

struct LiveStatsSnapshot: Sendable {
    var messages = 0
    var tokens = 0
    var toolCalls = 0
    var cost = 0.0
    var tokensByModel: [(model: String, tokens: Int)] = []
    var firstActivity: Date?
}

/// Computes today's stats by parsing JSONL session files directly.
/// Streaming chunks are deduplicated by `message.id` before usage is aggregated.
@Observable
@MainActor
final class LiveStatsService {
    private(set) var todayMessages: Int = 0
    private(set) var todayTokens: Int = 0
    private(set) var todayToolCalls: Int = 0
    private(set) var todayCost: Double = 0
    private(set) var tokensByModel: [(model: String, tokens: Int)] = []
    private(set) var firstActivityToday: Date?
    private(set) var isStale: Bool = false
    private(set) var lastParsed: Date?

    private let projectsDirectories: [String]
    private var timer: Timer?
    private var isParsing = false

    private let modelCatalogService: ModelCatalogService?

    init(claudeDir: String = "~/.claude", modelCatalogService: ModelCatalogService? = nil) {
        self.modelCatalogService = modelCatalogService
        let requestedProjects = NSString(string: claudeDir).expandingTildeInPath + "/projects"
        var directories = JSONLLocator.allProjectsDirectories()
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: requestedProjects, isDirectory: &isDirectory),
           isDirectory.boolValue,
           !directories.contains(requestedProjects) {
            directories.append(requestedProjects)
        }
        self.projectsDirectories = directories.sorted()
    }

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

    private func parseToday() {
        guard !isParsing else { return }
        isParsing = true
        let projectsDirectories = self.projectsDirectories
        let startOfDay = Calendar.current.startOfDay(for: Date())

        Task.detached(priority: .userInitiated) {
            let snapshot = Self.scanToday(
                projectsDirectories: projectsDirectories,
                startOfDay: startOfDay
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.apply(snapshot)
                self.lastParsed = Date()
                self.isParsing = false
            }
        }
    }

    /// Applies an already parsed snapshot; internal so parsing behavior can be tested deterministically.
    func apply(_ snapshot: LiveStatsSnapshot) {
        todayMessages = snapshot.messages
        todayTokens = snapshot.tokens
        todayToolCalls = snapshot.toolCalls
        todayCost = snapshot.cost
        tokensByModel = snapshot.tokensByModel
        modelCatalogService?.noteModels(snapshot.tokensByModel.map(\.model))
        firstActivityToday = snapshot.firstActivity
    }

    /// File mtime is only a prefilter; every assistant line must also be from today.
    nonisolated static func scanToday(
        projectsDirectories: [String],
        startOfDay: Date
    ) -> LiveStatsSnapshot {
        let fm = FileManager.default
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        var messagesByID: [String: (model: String, usage: [String: Any], toolCalls: Int)] = [:]
        var anonymousIndex = 0
        var firstActivity: Date?
        let paths = JSONLLocator.files(
            inProjectsDirectories: projectsDirectories,
            modifiedSince: startOfDay
        )

        for path in paths {
            autoreleasepool {
                guard let data = fm.contents(atPath: path),
                      let content = String(data: data, encoding: .utf8) else { return }
                for line in content.split(separator: "\n") {
                    guard let lineData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                          (json["type"] as? String) == "assistant",
                          let timestampString = json["timestamp"] as? String,
                          let timestamp = isoFractional.date(from: timestampString)
                            ?? isoBasic.date(from: timestampString),
                          timestamp >= startOfDay,
                          let message = json["message"] as? [String: Any]
                    else { continue }

                    if firstActivity.map({ timestamp < $0 }) ?? true {
                        firstActivity = timestamp
                    }
                    guard let usage = message["usage"] as? [String: Any] else { continue }
                    let model = message["model"] as? String ?? "unknown"
                    guard model != "<synthetic>" else { continue }

                    let messageID: String
                    if let id = message["id"] as? String, !id.isEmpty {
                        messageID = id
                    } else {
                        messageID = "<anonymous>:\(anonymousIndex)"
                        anonymousIndex += 1
                    }
                    let blocks = message["content"] as? [[String: Any]] ?? []
                    let toolCalls = blocks.filter { ($0["type"] as? String) == "tool_use" }.count
                    messagesByID[messageID] = (model, usage, toolCalls)
                }
            }
        }

        var snapshot = LiveStatsSnapshot()
        snapshot.messages = messagesByID.count
        snapshot.firstActivity = firstActivity
        var modelTokenCounts: [String: Int] = [:]
        for entry in messagesByID.values {
            let input = entry.usage["input_tokens"] as? Int ?? 0
            let output = entry.usage["output_tokens"] as? Int ?? 0
            let cacheRead = entry.usage["cache_read_input_tokens"] as? Int ?? 0
            let cacheWrite = entry.usage["cache_creation_input_tokens"] as? Int ?? 0
            let ioTokens = input + output
            snapshot.tokens += ioTokens
            snapshot.toolCalls += entry.toolCalls
            modelTokenCounts[entry.model, default: 0] += ioTokens
            snapshot.cost += messageCost(
                model: entry.model, input: input, output: output,
                cacheRead: cacheRead, cacheWrite: cacheWrite
            )
        }
        snapshot.tokensByModel = modelTokenCounts
            .map { (model: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }
        return snapshot
    }

    private func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.parseToday() }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private nonisolated static func messageCost(
        model: String, input: Int, output: Int,
        cacheRead: Int, cacheWrite: Int
    ) -> Double {
        CostCalculator.cost(
            modelId: model, input: input, output: output,
            cacheRead: cacheRead, cacheCreation: cacheWrite
        )
    }
}
