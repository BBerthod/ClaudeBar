import Foundation

struct GeminiActivity: Sendable, Equatable {
    var conversationsToday = 0
    var promptsToday = 0
    var activeConversations = 0
    var agentsToday: [String] = []
    var workspacesToday: [String] = []
    var lastPromptAt: Date?
    var isLoggedIn = false
}

enum GeminiActivityParser {
    static func parseSummaries(tsvRows: [String], startOfDay: Date) -> GeminiActivity {
        var activity = GeminiActivity()
        var agents = Set<String>()
        var workspaces = Set<String>()
        for row in tsvRows {
            let parts = row.components(separatedBy: "\t")
            guard parts.count == 7 else { continue }
            if parts[3] == "1", parts[4] == "0" { activity.activeConversations += 1 }
            guard let date = parseDate(parts[1]), date >= startOfDay else { continue }
            activity.conversationsToday += 1
            let agent = parts[5].trimmingCharacters(in: .whitespacesAndNewlines)
            if !agent.isEmpty { agents.insert(agent) }
            let paths = (try? JSONDecoder().decode([String].self, from: Data(parts[6].utf8))) ?? [parts[6]]
            for path in paths where !path.isEmpty {
                let url = path.hasPrefix("file://") ? URL(string: path) : URL(fileURLWithPath: path)
                if let name = url?.lastPathComponent, !name.isEmpty { workspaces.insert(name) }
            }
        }
        activity.agentsToday = agents.sorted()
        activity.workspacesToday = workspaces.sorted()
        return activity
    }

    static func parseHistory(lines: [String], startOfDay: Date) -> (promptsToday: Int, lastPromptAt: Date?) {
        struct Entry: Decodable { let timestamp: Double }
        var count = 0
        var last: Date?
        for line in lines {
            guard let entry = try? JSONDecoder().decode(Entry.self, from: Data(line.utf8)),
                  entry.timestamp.isFinite else { continue }
            let date = Date(timeIntervalSince1970: entry.timestamp / 1000)
            if date >= startOfDay { count += 1 }
            if last == nil || date > last! { last = date }
        }
        return (count, last)
    }

    static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        var normalized = s
        if let space = normalized.firstIndex(of: " ") { normalized.replaceSubrange(space...space, with: "T") }
        for value in [s, normalized] {
            for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
                iso.formatOptions = options
                if let date = iso.date(from: value) { return date }
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        for format in ["yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: s) { return date }
        }
        return nil
    }
}
