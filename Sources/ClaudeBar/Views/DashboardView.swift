import SwiftUI
import Charts

struct DashboardView: View {
    var statsService: StatsService
    var sessionService: SessionService
    var burnRateService: BurnRateService
    var usageService: UsageService
    var liveStatsService: LiveStatsService

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

    // MARK: - 7-day sparkline data

    private var sevenDaySparklineData: [Int] {
        statsService.last30DaysActivity.suffix(7).map(\.messageCount)
    }

    // MARK: - Human cost (ROI)

    private var devHoursEquivalent: Double {
        Double(effectiveMessages) * 3.0 / 60.0
    }

    private var devCostEquivalent: Double {
        devHoursEquivalent * 150.0
    }

    private var roiMultiplier: Double {
        devCostEquivalent / max(effectiveCost, 0.01)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header: Today label | 7-day sparkline | cost + 5h gauge
                HStack(alignment: .center, spacing: 8) {
                    // Left: date label
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today")
                            .font(.headline)
                        Text(formattedDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Center: 7-day sparkline (only when data exists)
                    if !sevenDaySparklineData.isEmpty {
                        Chart {
                            ForEach(sevenDaySparklineData.indices, id: \.self) { index in
                                BarMark(
                                    x: .value("Day", index),
                                    y: .value("Messages", sevenDaySparklineData[index])
                                )
                                .foregroundStyle(Color.accentColor.opacity(0.6))
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartLegend(.hidden)
                        .frame(width: 60, height: 30)
                    }

                    Spacer()

                    // Right: cost + 5h gauge stacked
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(CostCalculator.formatCost(effectiveCost))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            HStack(spacing: 3) {
                                if liveStatsService.isStale {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 7))
                                        .foregroundStyle(.orange)
                                }
                                Text(liveStatsService.isStale ? "live estimate" : "estimated cost")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // 5h circular arc gauge (only when data available)
                        if let fiveHour = usageService.usage?.fiveHour {
                            fiveHourArcGauge(utilization: fiveHour.utilization)
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

                // Burn Rate indicator
                if let rate = burnRateService.burnRate {
                    burnRateCard(rate)
                        .padding(.horizontal, 12)
                }

                // Human cost comparison row
                if effectiveCost > 0 && effectiveMessages > 0 {
                    humanCostRow
                        .padding(.horizontal, 12)
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

            Text("×\(Int(roiMultiplier)) ROI")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.primary.opacity(0.03))
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
                if let pace {
                    Text(pace.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(paceColor(pace))
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
                        .foregroundStyle(paceColor(pace))
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

    private func paceColor(_ pace: PaceLevel) -> Color {
        switch pace {
        case .comfortable: return .green
        case .onTrack:     return .blue
        case .warming:     return .yellow
        case .pressing:    return .orange
        case .critical:    return .red
        case .runaway:     return .red
        }
    }

    // MARK: - Burn Rate Card

    @ViewBuilder
    private func burnRateCard(_ rate: BurnRate) -> some View {
        HStack(spacing: 10) {
            // Zone icon + label
            HStack(spacing: 5) {
                Image(systemName: zoneIcon(rate.zone))
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
                Text("\(Int(rate.percentOfAverage))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(rate.percentOfAverage > 150 ? zoneColor(rate.zone) : .primary)
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

    private func modelColor(for modelId: String) -> Color {
        let name = StatsService.displayName(for: modelId).lowercased()
        if name.contains("opus")   { return .opusColor }
        if name.contains("sonnet") { return .sonnetColor }
        if name.contains("haiku")  { return .haikuColor }
        return .secondary
    }

    private func zoneColor(_ zone: PacingZone) -> Color {
        switch zone {
        case .chill:    return .blue
        case .onTrack:  return .green
        case .hot:      return .orange
        case .critical: return .red
        }
    }

    private func zoneIcon(_ zone: PacingZone) -> String {
        switch zone {
        case .chill:    return "snowflake"
        case .onTrack:  return "checkmark.circle"
        case .hot:      return "flame"
        case .critical: return "flame.fill"
        }
    }
}

#Preview {
    DashboardView(
        statsService: StatsService(),
        sessionService: SessionService(),
        burnRateService: BurnRateService(),
        usageService: UsageService(),
        liveStatsService: LiveStatsService()
    )
    .frame(width: 420, height: 480)
}
