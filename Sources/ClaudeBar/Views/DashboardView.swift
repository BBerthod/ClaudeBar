import SwiftUI

struct DashboardView: View {
    var statsService: StatsService
    var sessionService: SessionService
    var burnRateService: BurnRateService
    var usageService: UsageService
    var liveStatsService: LiveStatsService
    var mcpHealthService: McpHealthService
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
            details: nil
        )

        let hasGemini = mcpHealthService.hasGeminiConfigured || statsService.tokensByModelToday.contains {
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

    // MARK: - 7-day sparkline data

    private var sevenDaySparklineData: [Int] {
        statsService.last30DaysActivity.suffix(7).map(\.messageCount)
    }

    // MARK: - Human cost (ROI)

    private var devHoursEquivalent: Double {
        HumanCostCalculator.estimateHumanHours(messages: effectiveMessages, toolCalls: effectiveToolCalls)
    }

    private var devCostEquivalent: Double {
        HumanCostCalculator.estimateHumanCost(messages: effectiveMessages, toolCalls: effectiveToolCalls)
    }

    private var roiMultiplier: Double {
        HumanCostCalculator.roiMultiplier(humanCost: devCostEquivalent, claudeCost: effectiveCost)
    }

    // MARK: - Cache Savings

    /// How much prompt caching saved vs paying full input price for those tokens.
    private var cacheSavings: Double {
        guard let modelUsage = statsService.stats?.modelUsage else { return 0 }
        let mTok = 1_000_000.0
        var savings = 0.0
        for (modelId, usage) in modelUsage {
            let p = CostCalculator.pricing(for: modelId)
            let cacheReadTokens = Double(usage.cacheReadInputTokens)
            savings += cacheReadTokens * (p.inputPerMTok - p.cacheReadPerMTok) / mTok
        }
        return savings
    }

    /// Cache savings as a percentage of what the total cost would have been without caching.
    private var cacheSavingsPercent: Double {
        guard let modelUsage = statsService.stats?.modelUsage else { return 0 }
        let mTok = 1_000_000.0
        var fullPrice = 0.0
        var discountedPrice = 0.0
        for (modelId, usage) in modelUsage {
            let p = CostCalculator.pricing(for: modelId)
            let cacheReadTokens = Double(usage.cacheReadInputTokens)
            fullPrice += cacheReadTokens * p.inputPerMTok / mTok
            discountedPrice += cacheReadTokens * p.cacheReadPerMTok / mTok
        }
        guard fullPrice > 0 else { return 0 }
        return (fullPrice - discountedPrice) / fullPrice * 100
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header: Today label | 7-day sparkline | cost + 5h gauge
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

                    // Center: 7-day sparkline
                    Sparkline(data: sevenDaySparklineData)
                        .help("Message count trend over the last 7 days")

                    Spacer()

                    // Right: cost + 5h gauge stacked
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(CostCalculator.formatCost(effectiveCost))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .help("API-equivalent cost (not what you pay on Max subscription)")
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

                        // 5h circular arc gauge (only when data available)
                        if let fiveHour = usageService.usage?.fiveHour {
                            fiveHourArcGauge(utilization: fiveHour.utilization)
                                .help("Anthropic rate limit — resets every 5 hours")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // Provider summary pills
                providerSummary
                    .padding(.horizontal, 12)

                // Rate limit usage (live from API)
                if usageService.usage != nil {
                    usageSection
                        .padding(.horizontal, 12)
                }

                // Burn Rate indicator + 5h projection
                if let rate = burnRateService.burnRate {
                    VStack(alignment: .leading, spacing: 4) {
                        burnRateCard(rate)
                            .help("Compares today's projected cost to your 30-day average")

                        // 5h window projection
                        if let fiveHour = usageService.usage?.fiveHour,
                           let pace = usageService.fiveHourPace {
                            let projected = fiveHour.utilization / max(usageService.fiveHourElapsedFraction, 0.05)
                            HStack(spacing: 4) {
                                Text("5h projected: \(Int(min(projected, 999)))%")
                                    .font(.caption2)
                                    .foregroundStyle(projected > 100 ? .red : .secondary)
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text(pace.rawValue)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(projected > 100 ? .red : .secondary)
                            }
                            .padding(.leading, 4)
                        }
                    }
                    .padding(.horizontal, 12)
                }

                // Human cost comparison row
                if effectiveCost > 0 && effectiveMessages > 0 {
                    humanCostRow
                        .padding(.horizontal, 12)
                }

                // Cache savings row
                if cacheSavings > 0.001 {
                    cacheSavingsRow
                        .padding(.horizontal, 12)
                }

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

                // Active sessions
                if !sessionService.activeSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Active Sessions")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            // Longest session badge
                            if let longest = sessionService.activeSessions.max(by: { $0.duration < $1.duration }) {
                                Text("longest: \(longest.duration.formattedDuration)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

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
                            .contentShape(Rectangle())
                            .onTapGesture {
                                ProcessHelper.focusTerminal(forChildPID: session.pid)
                            }
                            .onHover { hovering in
                                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

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
                        .padding(.vertical, 4)
                    }
                } else if sessionService.activeSessions.isEmpty {
                    emptyState
                }

                Spacer(minLength: 12)
            }
        }
    }

    // MARK: - 5h Circular Arc Gauge

    @ViewBuilder
    private func fiveHourArcGauge(utilization: Double) -> some View {
        let ratio = min(utilization / 100.0, 1.0)
        let startAngle: Double = -130
        let sweepAngle: Double = 260
        let strokeWidth: CGFloat = 6

        // Gradient color: green → orange at 70% → red at 90%+
        let gaugeColor: Color = {
            switch utilization {
            case ..<70:  return .green
            case 70..<90: return .orange
            default:      return .red
            }
        }()

        ZStack {
            // Background track
            Circle()
                .trim(from: 0, to: CGFloat(sweepAngle / 360.0))
                .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(startAngle))

            // Foreground fill
            Circle()
                .trim(from: 0, to: CGFloat(sweepAngle / 360.0) * ratio)
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(startAngle))
                .animation(.easeOut(duration: 0.4), value: ratio)

            // Center label
            VStack(spacing: 0) {
                Text("\(Int(utilization))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text("5h")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
    }

    // MARK: - Human Cost Row

    private var humanCostRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.badge.clock")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("≈ \(Int(devHoursEquivalent * 60)) dev-min")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if roiMultiplier > 0 {
                Text("×\(Int(roiMultiplier)) ROI")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
                    .help("How many times cheaper Claude is vs equivalent developer time")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Cache Savings Row

    private var cacheSavingsRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 12))
                .foregroundStyle(.green)

            Text("Cache saved \(CostCalculator.formatCost(cacheSavings))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if cacheSavingsPercent > 0 {
                Text("\(Int(cacheSavingsPercent))% cheaper")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
                    .help("Percentage saved on cache-eligible tokens vs full input price")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.green.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    // MARK: - Usage Section

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rate Limits")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                HStack(spacing: 4) {
                    Text(usageService.plan.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                    Text(usageService.tier.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Capsule())
            }

            if let fiveHour = usageService.usage?.fiveHour {
                fiveHourGauge(fiveHour: fiveHour, pace: usageService.fiveHourPace)
            }

            if let sevenDay = usageService.usage?.sevenDay {
                usageBar(
                    label: "7d Window",
                    utilization: sevenDay.utilization,
                    timeRemaining: sevenDay.timeRemaining,
                    pace: usageService.sevenDayPace
                )
            }

            if let sonnet = usageService.usage?.sevenDaySonnet {
                usageBar(
                    label: "Sonnet 7d",
                    utilization: sonnet.utilization,
                    timeRemaining: sonnet.timeRemaining,
                    pace: nil
                )
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func fiveHourGauge(fiveHour: UsageWindow, pace: PaceLevel?) -> some View {
        HStack(spacing: 12) {
            // Circular gauge
            Gauge(value: min(fiveHour.utilization, 100), in: 0...100) {
                // Label (not shown in accessoryCircular)
            } currentValueLabel: {
                Text("\(Int(fiveHour.utilization))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [.green, .yellow, .orange, .red]))
            .scaleEffect(0.8)
            .frame(width: 44, height: 44)

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text("5h Window")
                    .font(.caption)
                    .fontWeight(.medium)
                if let remaining = fiveHour.timeRemaining {
                    Text("Resets in \(remaining)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let eta = etaToLimit(window: fiveHour, windowHours: 5) {
                    Text(eta)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let pace {
                    Text(pace.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(pace.color)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func usageBar(label: String, utilization: Double, timeRemaining: String?, pace: PaceLevel?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let pace {
                    Text(pace.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(pace.color)
                }
                Text("\(Int(utilization))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                if let remaining = timeRemaining {
                    Text("(\(remaining))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(utilizationColor(utilization))
                        .frame(width: geo.size.width * min(utilization / 100, 1.0), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func utilizationColor(_ pct: Double) -> Color {
        switch pct {
        case ..<30:   return .green
        case 30..<60: return .blue
        case 60..<80: return .orange
        default:      return .red
        }
    }

    // MARK: - Burn Rate Card

    @ViewBuilder
    private func burnRateCard(_ rate: BurnRate) -> some View {
        HStack(spacing: 10) {
            // Zone icon + label
            HStack(spacing: 5) {
                Image(systemName: rate.zone.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(zoneColor(rate.zone))
                Text(rate.zone.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(zoneColor(rate.zone))
            }

            Spacer()

            // Cost per hour
            VStack(alignment: .trailing, spacing: 1) {
                Text(rate.costPerHourFormatted)
                    .font(.caption)
                    .fontWeight(.medium)
                Text("/hr")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 1, height: 24)

            // Projected daily cost
            VStack(alignment: .trailing, spacing: 1) {
                Text(rate.projectedCostFormatted)
                    .font(.caption)
                    .fontWeight(.medium)
                Text("projected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 1, height: 24)

            // % of average
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Int(rate.percentOfAverage * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(rate.percentOfAverage > 1.5 ? zoneColor(rate.zone) : .primary)
                Text("of avg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(zoneColor(rate.zone).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(zoneColor(rate.zone).opacity(0.2), lineWidth: 0.5)
        )
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

    // MARK: - Helpers

    /// Estimates time until the rate limit window reaches 100%, based on the
    /// current utilization velocity (utilization consumed per elapsed hour).
    private func etaToLimit(window: UsageWindow, windowHours: Double) -> String? {
        guard window.utilization > 0, window.utilization < 95 else { return nil }
        guard let resetDate = window.resetDate else { return nil }

        let windowStart = resetDate.addingTimeInterval(-windowHours * 3600)
        let elapsed = max(Date().timeIntervalSince(windowStart), 1)
        let elapsedHours = elapsed / 3600

        let ratePerHour = window.utilization / elapsedHours
        guard ratePerHour > 0 else { return nil }

        let remainingPct = 100.0 - window.utilization
        let hoursToFull = remainingPct / ratePerHour

        if hoursToFull > 48 { return nil }

        let h = Int(hoursToFull)
        let m = Int((hoursToFull - Double(h)) * 60)
        if h > 0 {
            return "~full in \(h)h \(m)m"
        }
        return "~full in \(m)m"
    }

    private func zoneColor(_ zone: PacingZone) -> Color {
        switch zone {
        case .chill:    return .blue
        case .onTrack:  return .green
        case .hot:      return .orange
        case .critical: return .red
        }
    }

}


#Preview {
    DashboardView(
        statsService: StatsService(),
        sessionService: SessionService(),
        burnRateService: BurnRateService(),
        usageService: UsageService(),
        liveStatsService: LiveStatsService(),
        mcpHealthService: McpHealthService()
    )
    .frame(width: 420, height: 480)
}
