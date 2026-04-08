import Foundation

struct ProjectStats: Identifiable, Comparable, Sendable {
    let projectPath: String
    let projectName: String
    var sessionCount: Int
    var totalMessages: Int
    var branches: Set<String>
    var lastActive: Date?
    var estimatedCost: Double  // rough estimate based on message count ratio
    var dailyMessageCounts: [Int] = []  // last 7 days message distribution

    var id: String { projectPath }

    static func < (lhs: ProjectStats, rhs: ProjectStats) -> Bool {
        lhs.estimatedCost > rhs.estimatedCost // sort by cost descending
    }
}
