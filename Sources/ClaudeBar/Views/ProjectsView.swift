import SwiftUI
import Charts

struct ProjectsView: View {
    var projectService: ProjectService
    var statsService: StatsService

    @State private var sortBy: ProjectSort = .cost
    @State private var searchText: String = ""

    enum ProjectSort: String, CaseIterable {
        case cost = "Cost"
        case sessions = "Sessions"
        case recent = "Recent"
    }

    private var sortedProjects: [ProjectStats] {
        let base: [ProjectStats]
        switch sortBy {
        case .cost:
            base = projectService.projects.sorted { $0.estimatedCost > $1.estimatedCost }
        case .sessions:
            base = projectService.projects.sorted { $0.sessionCount > $1.sessionCount }
        case .recent:
            base = projectService.projects.sorted { lhs, rhs in
                switch (lhs.lastActive, rhs.lastActive) {
                case let (l?, r?): return l > r
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return false
                }
            }
        }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.projectName.localizedCaseInsensitiveContains(searchText) }
    }

    private var totalEstimatedCost: Double {
        projectService.projects.reduce(0) { $0 + $1.estimatedCost }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Summary bar
                summaryBar
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                // Search field (only when there are enough projects)
                if projectService.projects.count > 5 {
                    TextField("Search projects…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 12)
                }

                // Sort picker
                Picker("Sort by", selection: $sortBy) {
                    ForEach(ProjectSort.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)

                if projectService.projects.isEmpty {
                    emptyState
                } else {
                    // Project list
                    ForEach(sortedProjects) { project in
                        projectCard(project)
                            .padding(.horizontal, 12)
                    }

                    // Work distribution chart
                    workDistributionChart
                        .padding(.horizontal, 12)
                }

                Spacer(minLength: 12)
            }
        }
    }

    // MARK: - Summary bar

    /// Per-model cost breakdown across all time.
    private var modelCostBreakdown: [(model: String, cost: Double)] {
        guard let stats = statsService.stats else { return [] }
        return CostCalculator.modelCostBreakdown(stats: stats)
    }

    private var summaryBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Projects")
                        .font(.headline)
                    Text("\(projectService.totalProjects) tracked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CostCalculator.formatCost(statsService.totalCostEstimate))
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("total cost")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Model cost split
            if !modelCostBreakdown.isEmpty {
                HStack(spacing: 8) {
                    ForEach(modelCostBreakdown, id: \.model) { entry in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.color(for: entry.model))
                                .frame(width: 6, height: 6)
                            Text(entry.model)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(CostCalculator.formatCost(entry.cost))
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Project card

    @ViewBuilder
    private func projectCard(_ project: ProjectStats) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Title row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.projectName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(project.projectPath)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if project.dailyMessageCounts.contains(where: { $0 > 0 }) {
                        Sparkline(data: project.dailyMessageCounts)
                            .frame(width: 48, height: 18)
                    }
                    Text(CostCalculator.formatCost(project.estimatedCost))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(costColor(for: project.estimatedCost))
                }

                // Stats row
                HStack(spacing: 12) {
                    Label("\(project.sessionCount) sessions", systemImage: "rectangle.stack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("\(project.totalMessages) msgs", systemImage: "message")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let lastActive = project.lastActive {
                        Text(lastActive.timeAgoString)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Cost bar relative to total
                if totalEstimatedCost > 0 && project.estimatedCost > 0 {
                    let ratio = min(project.estimatedCost / totalEstimatedCost, 1.0)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(costColor(for: project.estimatedCost))
                                .frame(width: geo.size.width * ratio, height: 4)
                        }
                    }
                    .frame(height: 4)
                }

                // Git branches
                if !project.branches.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(project.branches.sorted()), id: \.self) { branch in
                                branchPill(branch)
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private func branchPill(_ branch: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9))
            Text(branch)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Work distribution chart

    private var top10BySessions: [ProjectStats] {
        sortedProjects
            .sorted { $0.sessionCount > $1.sessionCount }
            .prefix(10)
            .filter { $0.sessionCount > 0 }
            .map { $0 }
    }

    private var workDistributionChart: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if top10BySessions.isEmpty {
                    Text("No session data")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(8)
                } else {
                    Chart(top10BySessions) { project in
                        BarMark(
                            x: .value("Sessions", project.sessionCount),
                            y: .value("Project", project.projectName)
                        )
                        .foregroundStyle(costColor(for: project.estimatedCost).gradient)
                        .annotation(position: .trailing) {
                            Text("\(project.sessionCount)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(top10BySessions.count) * 28)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
            }
            .padding(4)
        } label: {
            Text("Work Distribution (sessions)")
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No projects found")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Projects appear here once you use Claude Code in a directory.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 12)
    }

    // MARK: - Helpers

    private func costColor(for cost: Double) -> Color {
        switch cost {
        case ..<1:    return .secondary
        case ..<5:    return .yellow
        case ..<20:   return Color.orange
        default:      return .red
        }
    }

}

#Preview {
    ProjectsView(
        projectService: ProjectService(),
        statsService: StatsService()
    )
    .frame(width: 420, height: 520)
}
