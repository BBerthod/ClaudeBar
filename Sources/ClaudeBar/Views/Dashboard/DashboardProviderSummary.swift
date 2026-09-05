import SwiftUI

struct DashboardProviderSummary: View {
    @Environment(GeminiActivityService.self) private var geminiActivityService
    @Environment(OmlxUsageService.self) private var omlxUsageService
    let statsService: StatsService
    let mcpHealthService: McpHealthService
    let providerUsageService: ProviderUsageService
    let omlxMonitorService: OmlxMonitorService

    var body: some View {
        providerSummary
    }
    /// Derives active provider information from available stats.
    private var providers: [ProviderInfo] {
        let claudeConfigured = statsService.todayTokens > 0 || statsService.totalCostEstimate > 0
        let claudeTokens = statsService.todayTokens
        let claudeProvider = ProviderInfo(
            name: "Claude",
            icon: "brain.head.profile",
            isConfigured: true,
            totalTokens: claudeTokens > 0 ? claudeTokens : nil,
            estimatedCost: claudeConfigured ? statsService.todayCostEstimate : nil,
            details: nil,
            sessionCount: nil,
            contextLimitHits: nil
        )

        let hasCodex = mcpHealthService.hasCodexConfigured || statsService.tokensByModelToday.contains {
            $0.model.lowercased().contains("codex") || $0.model.lowercased().contains("gpt")
        }
        let codexProvider = ProviderInfo(
            name: "Codex",
            icon: "chevron.left.forwardslash.chevron.right",
            isConfigured: hasCodex || providerUsageService.isCodexAvailable,
            totalTokens: providerUsageService.isCodexAvailable ? providerUsageService.codexTokensToday : nil,
            estimatedCost: nil,
            details: (hasCodex || providerUsageService.isCodexAvailable) ? nil : "Not tracked",
            sessionCount: providerUsageService.isCodexAvailable ? providerUsageService.codexSessionsToday : nil,
            contextLimitHits: providerUsageService.codexContextLimitHitsToday > 0 ? providerUsageService.codexContextLimitHitsToday : nil
        )

        return [claudeProvider, codexProvider]
    }

    // MARK: - Provider Summary

    private var providerSummary: some View {
        HStack(spacing: 8) {
            ForEach(providers) { provider in
                providerPill(provider)
                if provider.name == "Claude" {
                    geminiCard
                }
            }
            if omlxUsageService.isAvailable {
                omlxCard
            }
            Spacer()
        }
    }

    private var geminiCard: some View {
        let activity = geminiActivityService.activity
        let installed = geminiActivityService.isInstalled
        return VStack(alignment: .leading, spacing: 2) {
            Label("Gemini", systemImage: "sparkles")
                .fontWeight(.medium)
            if installed {
                Text("\(activity.promptsToday) prompts · \(activity.conversationsToday) conversations today")
                if activity.activeConversations > 0 {
                    Text("\(activity.activeConversations) active")
                        .padding(.horizontal, 4)
                        .background(Color.green.opacity(0.15))
                        .clipShape(Capsule())
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(activity.isLoggedIn ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 5, height: 5)
                    Text(activity.isLoggedIn ? "logged in" : "logged out")
                }
            } else {
                Text("Antigravity not installed")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption2)
        .foregroundStyle(installed ? .primary : .secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(installed ? Color.green.opacity(0.1) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(installed ? Color.green.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .help("Antigravity does not expose token counts — activity only")
    }

    private var omlxCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("oMLX", systemImage: "cpu.fill")
                .fontWeight(.medium)
            Text("\(omlxUsageService.today?.totals.requests ?? 0) req today")
            Text("\((omlxUsageService.today?.totals.completionTokens ?? 0).abbreviatedTokenCount) output tokens")
            if let model = omlxUsageService.loadedModels.first(where: { $0.isLoaded })?.id
                ?? omlxMonitorService.defaultModel {
                Text(model)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model)
            }
            Text("≈ \(CostCalculator.formatCost(omlxUsageService.todayApiEquivalentCost)) saved")
                .help("API-equivalent cost if these tokens had gone to \(omlxUsageService.referenceModelId)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.3), lineWidth: 0.5))
    }

    @ViewBuilder
    private func providerPill(_ provider: ProviderInfo) -> some View {
        let hasUsageData = provider.sessionCount != nil || provider.totalTokens != nil

        VStack(alignment: .leading, spacing: 2) {
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

            if hasUsageData {
                HStack(spacing: 3) {
                    if let sessions = provider.sessionCount, sessions > 0 {
                        Text("\(sessions) sess")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if provider.sessionCount != nil, provider.totalTokens != nil {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let tokens = provider.totalTokens, tokens > 0 {
                        Text(tokens.abbreviatedTokenCount)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let hits = provider.contextLimitHits {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(hits)⚠")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            } else if let details = provider.details {
                Text(details)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            provider.isConfigured
                ? Color.green.opacity(0.1)
                : Color.secondary.opacity(0.08)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    provider.isConfigured
                        ? Color.green.opacity(0.3)
                        : Color.secondary.opacity(0.15),
                    lineWidth: 0.5
                )
        )
    }
}

