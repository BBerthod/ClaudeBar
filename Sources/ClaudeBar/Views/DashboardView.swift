import SwiftUI

struct DashboardView: View {
    var statsService: StatsService
    var sessionService: SessionService

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today")
                            .font(.headline)
                        Text(formattedDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(statsService.todayCostFormatted)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("estimated cost")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // Stats grid (2x2)
                if statsService.todayMessages == 0 && statsService.todaySessions == 0 {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        StatCard(
                            title: "Messages",
                            value: "\(statsService.todayMessages)",
                            icon: "message"
                        )
                        StatCard(
                            title: "Sessions",
                            value: "\(statsService.todaySessions)",
                            icon: "rectangle.stack"
                        )
                        StatCard(
                            title: "Tool Calls",
                            value: "\(statsService.todayToolCalls)",
                            icon: "wrench.and.screwdriver"
                        )
                        StatCard(
                            title: "Tokens",
                            value: statsService.todayTokens.abbreviatedTokenCount,
                            icon: "text.word.spacing"
                        )
                    }
                    .padding(.horizontal, 12)

                    // Token distribution by model
                    if !statsService.tokensByModelToday.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tokens by Model")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)

                            TokenBar(segments: statsService.tokensByModelToday)
                                .frame(height: 28)
                                .padding(.horizontal, 12)

                            // Legend
                            HStack(spacing: 12) {
                                ForEach(statsService.tokensByModelToday, id: \.model) { entry in
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(modelColor(for: entry.model))
                                            .frame(width: 8, height: 8)
                                        Text(StatsService.displayName(for: entry.model))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(entry.tokens.abbreviatedTokenCount)
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                        .padding(.vertical, 4)
                    }

                    // Active sessions
                    if !sessionService.activeSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Active Sessions")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(sessionService.activeSessions.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 12)

                            ForEach(sessionService.activeSessions) { session in
                                SessionRow(
                                    projectName: session.projectName,
                                    detail: session.cwd,
                                    duration: session.duration.formattedDuration,
                                    isActive: true
                                )
                                .padding(.horizontal, 12)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Spacer(minLength: 12)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "moon.zzz")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No activity today")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Start a Claude Code session to see stats here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func modelColor(for modelId: String) -> Color {
        let name = StatsService.displayName(for: modelId).lowercased()
        if name.contains("opus")   { return .opusColor }
        if name.contains("sonnet") { return .sonnetColor }
        if name.contains("haiku")  { return .haikuColor }
        return .secondary
    }
}

#Preview {
    DashboardView(
        statsService: StatsService(),
        sessionService: SessionService()
    )
    .frame(width: 420, height: 480)
}
