import XCTest
@testable import ClaudeBarLib

final class ProjectStatsTests: XCTestCase {

    private func project(_ name: String, cost: Double) -> ProjectStats {
        ProjectStats(
            projectPath: "/tmp/\(name)",
            projectName: name,
            sessionCount: 1,
            totalMessages: 1,
            branches: [],
            lastActive: nil,
            estimatedCost: cost
        )
    }

    func testTotalEstimatedCostSumsProjectCosts() {
        let projects = [project("a", cost: 4461.70), project("b", cost: 2171.60), project("c", cost: 0.5)]
        XCTAssertEqual(projects.totalEstimatedCost, 6633.80, accuracy: 0.001)
    }

    func testTotalEstimatedCostOfNoProjectsIsZero() {
        XCTAssertEqual([ProjectStats]().totalEstimatedCost, 0)
    }
}
