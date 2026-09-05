import SwiftUI

struct DashboardProviderSummary: View {
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

        let hasGemini = mcpHealthService.hasGeminiConfigured || statsService.tokensByModelToday.contains {
            $0.model.lowercased().contains("gemini")
        }
        let geminiProvider = ProviderInfo(
            name: "Gemini",
            icon: "sparkles",
            isConfigured: hasGemini || providerUsageService.isGeminiAuthenticated,
            totalTokens: nil,
            estimatedCost: nil,
            details: providerUsageService.isGeminiAuthenticated
                ? (providerUsageService.geminiTokenValid ? nil : "Token expired")
                : "Not configured",
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

        let hasOmlxMcp = mcpHealthService.servers.contains {
            $0.name.lowercased().contains("omlx")
        }
        let omlxProvider = ProviderInfo(
            name: "oMLX",
            icon: "cpu.fill",
            isConfigured: omlxMonitorService.isOnline || hasOmlxMcp,
            totalTokens: nil,
            estimatedCost: nil,
            details: omlxMonitorService.isOnline
                ? omlxMonitorService.defaultModel
                : (hasOmlxMcp ? "Offline" : nil),
            sessionCount: providerUsageService.omlxCallsToday > 0
                ? providerUsageService.omlxCallsToday
                : nil,
            contextLimitHits: nil
        )
        return [claudeProvider, geminiProvider, codexProvider, omlxProvider]
    }

    // MARK: - Provider Summary

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

