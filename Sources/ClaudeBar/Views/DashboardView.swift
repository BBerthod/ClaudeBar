import SwiftUI


struct DashboardView: View {
    @Environment(StatsService.self) private var statsService
    @Environment(SessionService.self) private var sessionService
    @Environment(BurnRateService.self) private var burnRateService
    @Environment(UsageService.self) private var usageService
    @Environment(LiveStatsService.self) private var liveStatsService
    @Environment(McpHealthService.self) private var mcpHealthService
    @Environment(ProviderUsageService.self) private var providerUsageService
    @Environment(UpdateCheckService.self) private var updateCheckService
    @Environment(OmlxMonitorService.self) private var omlxMonitorService
    var onRefresh: (() -> Void)?

    // MARK: - Effective stats (prefer stats-cache, fallback to live JSONL)

    private var effectiveMessages: Int {
        statsService.todayMessages > 0 ? statsService.todayMessages : liveStatsService.todayMessages
    }

    private var effectiveSessions: Int {
        statsService.todaySessions > 0 ? statsService.todaySessions : sessionService.activeSessions.count
    }

    private var effectiveToolCalls: Int {
        statsService.todayToolCalls > 0 ? statsService.todayToolCalls : liveStatsService.todayToolCalls
    }

    private var effectiveTokens: Int {
        statsService.todayTokens > 0 ? statsService.todayTokens : liveStatsService.todayTokens
    }

    private var effectiveCost: Double {
        statsService.todayCostEstimate > 0 ? statsService.todayCostEstimate : liveStatsService.todayCost
    }

    private var effectiveTokensByModel: [(model: String, tokens: Int)] {
        !statsService.tokensByModelToday.isEmpty ? statsService.tokensByModelToday : liveStatsService.tokensByModel
    }

    private var hasStats: Bool {
        effectiveMessages > 0 || effectiveSessions > 0
    }

    private var estimatedCostHelp: String {
        effectiveTokensByModel
            .filter { $0.tokens > 0 && CostCalculator.isEstimated($0.model) }
            .map { entry in
                let basedOn = ModelCatalogService.current.resolve(entry.model)?.basedOn ?? "claude-opus-5"
                return "Estimated — \(entry.model) is priced like \(basedOn)"
            }
            .joined(separator: "\n")
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }

    /// Human-readable time since the last data refresh.
    private var lastRefreshTime: String? {
        // Pick the most recent update timestamp across data sources
        let candidates: [Date?] = [liveStatsService.lastParsed, usageService.lastFetched]
        guard let latest = candidates.compactMap({ $0 }).max() else { return nil }

        let seconds = Int(Date().timeIntervalSince(latest))
        if seconds < 10 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h \(minutes % 60)m ago"
    }


    // MARK: - 7-day sparkline data

    private var sevenDaySparklineData: [Int] {
        statsService.last30DaysActivity.suffix(7).map(\.messageCount)
    }


    private var dashboardSavingsRow: DashboardSavingsRow {
        DashboardSavingsRow(statsService: statsService)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Update banner
                if updateCheckService.updateAvailable, let version = updateCheckService.latestVersion {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.blue)
                        Text("ClaudeBar \(version) available")
                            .font(.caption)
                        Spacer()
                        if let url = updateCheckService.releaseURL.flatMap({ URL(string: $0) }) {
                            Button("View") {
                                NSWorkspace.shared.open(url)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12)
                }

                // Header: cost + date row
                HStack(alignment: .center, spacing: 8) {
                    // Left: date label + refresh
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("Today")
                                .font(.headline)
                            if let onRefresh {
                                Button(action: onRefresh) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Refresh all data")
                            }
                        }
                        HStack(spacing: 4) {
                            Text(formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let lastUpdate = lastRefreshTime {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(lastUpdate)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Spacer()

                    // Right: cost + 5h gauge
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(CostCalculator.formatCost(effectiveCost))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                    .help("API-equivalent cost (not what you pay on Max subscription)")
                                let estimatedHelp = estimatedCostHelp
                                if !estimatedHelp.isEmpty {
                                    Text("~")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .help(estimatedHelp)
                                }
                            }
                            HStack(spacing: 3) {
                                if liveStatsService.isStale {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 7))
                                        .foregroundStyle(.orange)
                                }
                                Text(liveStatsService.isStale ? "live estimate" : "estimated cost")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .help(liveStatsService.isStale ? "Computed from JSONL files — stats-cache hasn't updated yet" : "Estimated API-equivalent cost for today")
                            }
                        }

                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // Full-width 7-day sparkline
                Sparkline(data: sevenDaySparklineData)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .padding(.horizontal, 12)
                    .help("Message count trend over the last 7 days")

                DashboardProviderSummary(
                    statsService: statsService,
                    mcpHealthService: mcpHealthService,
                    providerUsageService: providerUsageService,
                    omlxMonitorService: omlxMonitorService
                )
                    .padding(.horizontal, 12)

                DashboardUsageSection(usageService: usageService)

                DashboardOptimizationHints(
                    statsService: statsService,
                    burnRateService: burnRateService,
                    effectiveTokensByModel: effectiveTokensByModel,
                    effectiveCost: effectiveCost,
                    cacheSavings: dashboardSavingsRow.cacheSavings
                )

                DashboardBurnRateCard(
                    burnRateService: burnRateService,
                    usageService: usageService
                )

                DashboardHumanCostRow(
                    effectiveMessages: effectiveMessages,
                    effectiveToolCalls: effectiveToolCalls,
                    effectiveCost: effectiveCost
                )

                dashboardSavingsRow

                // Extra Usage monthly cap (Max plan)
                if let extra = usageService.usage?.extraUsage, extra.isEnabled,
                   let limit = extra.monthlyLimit, let used = extra.usedCredits {
                    extraUsageRow(used: used, limit: limit)
                        .padding(.horizontal, 12)
                }

                // Speculation time saved
                if let ms = statsService.stats?.totalSpeculationTimeSavedMs, ms > 0 {
                    speculationRow(savedMs: ms)
                        .padding(.horizontal, 12)
                }

                DashboardActiveSessionsSection(sessionService: sessionService)

                // Stats grid (2x2)
                if hasStats {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        StatCard(title: "Messages", value: "\(effectiveMessages)", icon: "message")
                        StatCard(title: "Sessions", value: "\(effectiveSessions)", icon: "rectangle.stack")
                        StatCard(title: "Tool Calls", value: "\(effectiveToolCalls)", icon: "wrench.and.screwdriver")
                        StatCard(title: "Tokens", value: effectiveTokens.abbreviatedTokenCount, icon: "text.word.spacing")
                    }
                    .padding(.horizontal, 12)

                    if !effectiveTokensByModel.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tokens by Model")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)

                            TokenBar(segments: effectiveTokensByModel)
                                .frame(height: 28)
                                .padding(.horizontal, 12)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(effectiveTokensByModel, id: \.model) { entry in
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Color.color(for: entry.model))
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
                        }
                        .padding(.vertical, 4)
                    }
                } else if sessionService.activeSessions.isEmpty {
                    emptyState
                } else {
                    // Sessions actives mais pas encore de données
                    HStack {
                        Spacer()
                        Label("Session active — en attente de données…", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }

                Spacer(minLength: 12)
            }
        }
    }

    // MARK: - Extra Usage Row

    @ViewBuilder
    private func extraUsageRow(used: Double, limit: Double) -> some View {
        let pct = limit > 0 ? used / limit * 100 : 0
        HStack(spacing: 8) {
            Image(systemName: "creditcard")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Extra Usage")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "$%.2f / $%.0f", used, limit))
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
            Text("(\(Int(pct))%)")
                .font(.caption2)
                .foregroundStyle(pct > 80 ? .red : .secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Speculation Time Row

    @ViewBuilder
    private func speculationRow(savedMs: Int) -> some View {
        let seconds = savedMs / 1000
        let formatted: String = {
            if seconds >= 3600 {
                return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
            } else if seconds >= 60 {
                return "\(seconds / 60)m \(seconds % 60)s"
            }
            return "\(seconds)s"
        }()

        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12))
                .foregroundStyle(.yellow)
            Text("Speculation saved")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatted)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.yellow.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Empty State

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

}


#Preview {
    DashboardView()
        .environment(StatsService())
        .environment(SessionService())
        .environment(BurnRateService())
        .environment(UsageService())
        .environment(LiveStatsService())
        .environment(McpHealthService())
        .environment(ProviderUsageService())
        .environment(UpdateCheckService())
        .frame(width: 420, height: 480)
}
