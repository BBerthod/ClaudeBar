import Foundation

/// Parses JSONL session files to build a per-message ledger of API usage.
///
/// Each `LedgerEntry` represents one assistant message with its token counts,
/// estimated cost, and tool-call count. Entries are deduplicated by message ID
/// (last chunk wins, matching `LiveStatsService` behaviour).
@Observable
@MainActor
final class LedgerService {
    private(set) var entries: [LedgerEntry] = []
    private(set) var isLoading = false

    private let projectsDir: String

    init(claudeDir: String = "~/.claude") {
        self.projectsDir = NSString(string: claudeDir).expandingTildeInPath + "/projects"
    }

    // MARK: - Public

    /// Parse JSONL files modified within the last `days` days and populate `entries`.
    func load(days: Int = 7) {
        guard !isLoading else { return }
        isLoading = true

        let projectsDir = self.projectsDir
        let cutoffDays = days

        Task.detached(priority: .userInitiated) {
            let result = Self.parseEntries(projectsDir: projectsDir, days: cutoffDays)
            await MainActor.run { [weak self] in
                self?.entries = result
                self?.isLoading = false
            }
        }
    }

    // MARK: - Parsing (off main actor)

    private nonisolated static func parseEntries(projectsDir: String, days: Int) -> [LedgerEntry] {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970

        // Collect JSONL files modified after cutoff
        var jsonlFiles: [(path: String, projectName: String)] = []

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { return [] }
        for dir in projectDirs {
            let dirPath = projectsDir + "/" + dir

            // Direct session files
            if let files = try? fm.contentsOfDirectory(atPath: dirPath) {
                for file in files where file.hasSuffix(".jsonl") {
                    let path = dirPath + "/" + file
                    if let mtime = modTime(path, fm: fm), mtime >= cutoff {
                        jsonlFiles.append((path: path, projectName: dir))
                    }
                }
            }

            // Subagent files
            let subPath = dirPath + "/subagents"
            if let files = try? fm.contentsOfDirectory(atPath: subPath) {
                for file in files where file.hasSuffix(".jsonl") {
                    let path = subPath + "/" + file
                    if let mtime = modTime(path, fm: fm), mtime >= cutoff {
                        jsonlFiles.append((path: path, projectName: dir))
                    }
                }
            }
        }

        // Parse all files, dedup by message ID (last occurrence wins)
        struct RawEntry {
            let model: String
            let projectName: String
            let timestamp: Date
            let inputTokens: Int
            let outputTokens: Int
            let cacheReadTokens: Int
            let cacheWriteTokens: Int
            let toolCallCount: Int
        }

        var messagesByID: [String: RawEntry] = [:]

        for file in jsonlFiles {
            autoreleasepool {
                guard let data = fm.contents(atPath: file.path),
                      let content = String(data: data, encoding: .utf8) else { return }

                // Use file modification time as fallback timestamp
                let fileMtime = modTime(file.path, fm: fm).map { Date(timeIntervalSince1970: $0) } ?? Date()

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

                        // Count tool_use blocks
                        var toolCount = 0
                        if let blocks = message["content"] as? [[String: Any]] {
                            for block in blocks where (block["type"] as? String) == "tool_use" {
                                toolCount += 1
                            }
                        }

                        let inp = usage["input_tokens"] as? Int ?? 0
                        let out = usage["output_tokens"] as? Int ?? 0
                        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
                        let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0

                        messagesByID[msgID] = RawEntry(
                            model: model,
                            projectName: file.projectName,
                            timestamp: fileMtime,
                            inputTokens: inp,
                            outputTokens: out,
                            cacheReadTokens: cacheRead,
                            cacheWriteTokens: cacheWrite,
                            toolCallCount: toolCount
                        )
                    }
                }
            }
        }

        // Build LedgerEntry array with cost computation
        var result: [LedgerEntry] = []
        result.reserveCapacity(messagesByID.count)

        for (msgID, raw) in messagesByID {
            let cost = messageCost(
                model: raw.model,
                input: raw.inputTokens,
                output: raw.outputTokens,
                cacheRead: raw.cacheReadTokens,
                cacheWrite: raw.cacheWriteTokens
            )

            result.append(LedgerEntry(
                id: msgID,
                timestamp: raw.timestamp,
                model: raw.model,
                projectName: raw.projectName,
                inputTokens: raw.inputTokens,
                outputTokens: raw.outputTokens,
                cacheReadTokens: raw.cacheReadTokens,
                cacheWriteTokens: raw.cacheWriteTokens,
                estimatedCost: cost,
                toolCallCount: raw.toolCallCount
            ))
        }

        // Sort by timestamp descending (newest first)
        result.sort { $0.timestamp > $1.timestamp }
        return result
    }

    // MARK: - Helpers

    private nonisolated static func modTime(_ path: String, fm: FileManager) -> TimeInterval? {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else {
            return nil
        }
        return date.timeIntervalSince1970
    }

    /// Per-message cost using the shared CostCalculator pricing table.
    private nonisolated static func messageCost(
        model: String, input: Int, output: Int,
        cacheRead: Int, cacheWrite: Int
    ) -> Double {
        let p = CostCalculator.pricing(for: model)
        let mTok = 1_000_000.0
        return (Double(input)      * p.inputPerMTok +
                Double(output)     * p.outputPerMTok +
                Double(cacheRead)  * p.cacheReadPerMTok +
                Double(cacheWrite) * p.cacheWritePerMTok) / mTok
    }
}
