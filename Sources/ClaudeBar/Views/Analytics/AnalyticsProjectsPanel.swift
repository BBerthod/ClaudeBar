import SwiftUI
import AppKit
import Charts

struct AnalyticsProjectsPanel: View {
    let statsService: StatsService
    let projectService: ProjectService

    var body: some View {
        projectsPanel
    }
    @State private var projectSearch: String = ""
    @State private var copiedProjectPath: String?

    private var filteredProjects: [ProjectStats] {
        let sorted = projectService.projects.sorted { $0.estimatedCost > $1.estimatedCost }
        guard !projectSearch.isEmpty else { return sorted }
        return sorted.filter {
            $0.projectName.localizedCaseInsensitiveContains(projectSearch) ||
            $0.projectPath.localizedCaseInsensitiveContains(projectSearch)
        }
    }

    private var projectsPanel: some View {
        let projects = filteredProjects
        let totalCost = statsService.totalCostEstimate
        let totalMessages = projects.reduce(0) { $0 + $1.totalMessages }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Project Analytics")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)

                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter projects…", text: $projectSearch)
                        .textFieldStyle(.plain)
                    if !projectSearch.isEmpty {
                        Button {
                            projectSearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)

                // Summary
                HStack(spacing: 30) {
                    VStack(spacing: 2) {
                        Text("\(projects.count)")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("projects")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        Text(CostCalculator.formatCost(totalCost))
                            .font(.title)
                            .fontWeight(.bold)
                        Text("total cost")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        Text("\(totalMessages)")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("messages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)

                // Cost distribution chart
                if projects.count > 1 {
                    GroupBox("Cost Distribution") {
                        Chart(projects.prefix(10)) { project in
                            BarMark(
                                x: .value("Cost", project.estimatedCost),
                                y: .value("Project", project.projectName)
                            )
                            .foregroundStyle(projectCostColor(project.estimatedCost).gradient)
                            .annotation(position: .trailing) {
                                Text(CostCalculator.formatCost(project.estimatedCost))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartXAxis(.hidden)
                        .frame(height: CGFloat(min(projects.count, 10)) * 32)
                        .padding(8)
                    }
                    .padding(.horizontal)
                }

                // Project table
                GroupBox("All Projects") {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Project")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Sessions")
                                .frame(width: 65, alignment: .trailing)
                            Text("Messages")
                                .frame(width: 75, alignment: .trailing)
                            Text("Cost")
                                .frame(width: 80, alignment: .trailing)
                            Text("Dev Time")
                                .frame(width: 70, alignment: .trailing)
                            Text("Share")
                                .frame(width: 55, alignment: .trailing)
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                        Divider()

                        ForEach(projects) { project in
                            projectRow(project, totalCost: totalCost)

                            if project.id != projects.last?.id {
                                Divider().padding(.horizontal, 8)
                            }
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                if let copied = copiedProjectPath {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Copied: \(copied)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ project: ProjectStats, totalCost: Double) -> some View {
        let devHours = HumanCostCalculator.estimateHumanHours(
            messages: project.totalMessages,
            toolCalls: 0
        )
        let share = totalCost > 0 ? project.estimatedCost / totalCost * 100 : 0

        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(project.projectName)
                    .font(.subheadline)
                    .lineLimit(1)
                if let lastActive = project.lastActive {
                    Text(lastActive.timeAgoString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(project.sessionCount)")
                .font(.subheadline)
                .monospacedDigit()
                .frame(width: 65, alignment: .trailing)

            Text("\(project.totalMessages)")
                .font(.subheadline)
                .monospacedDigit()
                .frame(width: 75, alignment: .trailing)

            Text(CostCalculator.formatCost(project.estimatedCost))
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(projectCostColor(project.estimatedCost))
                .frame(width: 80, alignment: .trailing)

            Text(HumanCostCalculator.formatHours(devHours))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.blue)
                .frame(width: 70, alignment: .trailing)
                .help("Estimated equivalent dev time")

            Text(String(format: "%.0f%%", share))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 55, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.projectPath, forType: .string)
            withAnimation {
                copiedProjectPath = project.projectPath
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    if copiedProjectPath == project.projectPath {
                        copiedProjectPath = nil
                    }
                }
            }
        }
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func projectCostColor(_ cost: Double) -> Color {
        switch cost {
        case ..<1:    return .secondary
        case ..<5:    return .yellow
        case ..<20:   return .orange
        default:      return .red
        }
    }


    // MARK: - Sessions Panel

}
