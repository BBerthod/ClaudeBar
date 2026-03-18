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

    /// Derives active provider information from available stats.
    private var providers: [ProviderInfo] {
        // Claude is always present if we have any token activity
        let claudeConfigured = statsService.todayTokens > 0 || statsService.totalCostEstimate > 0
        let claudeTokens = statsService.todayTokens
        let claudeProvider = ProviderInfo(
            name: "Claude",
            icon: "brain.head.profile",
            isConfigured: true,
            totalTokens: claudeTokens > 0 ? claudeTokens : nil,
            estimatedCost: claudeConfigured ? statsService.todayCostEstimate : nil,
            details: nil
        )

        // Gemini: detected by looking for gemini model IDs in token usage
        let hasGemini = statsService.tokensByModelToday.contains {
            $0.model.lowercased().contains("gemini")
        }
        let geminiProvider = ProviderInfo(
            name: "Gemini",
            icon: "sparkles",
            isConfigured: hasGemini,
            totalTokens: nil,
            estimatedCost: nil,
            details: hasGemini ? nil : "Not tracked"
        )

        return [claudeProvider, geminiProvider]
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

                // Provider summary pills
                providerSummary
                    .padding(.horizontal, 12)

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

                    // Active sessions with context gauges
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
                                HStack(spacing: 6) {
                                    SessionRow(
                                        projectName: session.projectName,
                                        detail: session.cwd,
                                        duration: session.duration.formattedDuration,
                                        isActive: true
                                    )
                                    if let ctx = sessionService.contextEstimates[session.sessionId],
                                       ctx > 0 {
                                        ContextGauge(percentage: ctx, compact: true)
                                    }
                                }
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

    // MARK: - Provider summary

    private var providerSummary: some View {
        HStack(spacing: 8) {
            ForEach(providers) { provider in
                providerPill(provider)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func providerPill(_ provider: ProviderInfo) -> some View {
        HStack(spacing: 5) {
            Image(systemName: provider.icon)
                .font(.system(size: 10))
                .foregroundStyle(provider.isConfigured ? .primary : .secondary)

            Text(provider.name)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(provider.isConfigured ? .primary : .secondary)

            Circle()
                .fill(provider.isConfigured ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 5, height: 5)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            provider.isConfigured
                ? Color.green.opacity(0.1)
                : Color.secondary.opacity(0.08)
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    provider.isConfigured
                        ? Color.green.opacity(0.3)
                        : Color.secondary.opacity(0.15),
                    lineWidth: 0.5
                )
        )
    }

    // MARK: - Empty state

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

    // MARK: - Helpers

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
