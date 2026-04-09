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
        return [:]   // stub — implemented in Task 3
    }
}
