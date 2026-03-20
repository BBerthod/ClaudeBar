import SwiftUI

struct DesktopWidgetView: View {
    var usageService: UsageService
    var statsService: StatsService
    var sessionService: SessionService
    var onClose: () -> Void

    // MARK: - Computed

    private var utilization: Double {
        usageService.usage?.fiveHour?.utilization ?? 0
    }

    private var tokensFormatted: String {
        statsService.todayTokens.abbreviatedTokenCount
    }

    private var sessionCount: Int {
        sessionService.activeSessions.count
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

            mainRow
                .padding(.horizontal, 10)

            statusRow
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .frame(width: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 4) {
            // Drag-handle indicator
            Circle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 5, height: 5)

            Text("ClaudeBar")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(spacing: 10) {
            arcGauge

            VStack(alignment: .leading, spacing: 3) {
                // Tokens today
                HStack(spacing: 3) {
                    Image(systemName: "text.word.spacing")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(tokensFormatted)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }

                // Cost today
                HStack(spacing: 3) {
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(CostCalculator.formatCost(statsService.todayCostEstimate))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }

                // Active sessions
                HStack(spacing: 3) {
                    Circle()
                        .fill(sessionCount > 0 ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 5, height: 5)
                    Text("\(sessionCount) active")
                        .font(.system(size: 11))
                        .foregroundStyle(sessionCount > 0 ? .primary : .secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Arc Gauge

    /// 240° arc sweep centered at the bottom (lower-left → top → lower-right).
    private var arcGauge: some View {
        let fraction = min(utilization / 100.0, 1.0)
        let size: CGFloat = 52

        return ZStack {
            // Background arc
            Circle()
                .trim(from: 0, to: 2.0 / 3.0)
                .stroke(
                    Color.secondary.opacity(0.15),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(150))

            // Foreground arc
            Circle()
                .trim(from: 0, to: fraction * (2.0 / 3.0))
                .stroke(
                    gaugeColor(utilization),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(150))
                .animation(.easeInOut(duration: 0.4), value: fraction)

            // Center label
            VStack(spacing: 1) {
                if usageService.usage?.fiveHour != nil {
                    Text("\(Int(utilization))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(gaugeColor(utilization))
                } else {
                    Text("—")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Status Row

    private var statusRow: some View {
        HStack(spacing: 4) {
            if let fiveHour = usageService.usage?.fiveHour {
                Text("\(Int(fiveHour.utilization))% used")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let pace = usageService.fiveHourPace {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(pace.rawValue)
                        .font(.caption2)
                        .foregroundStyle(pace.color)
                }

                if let remaining = fiveHour.timeRemaining {
                    Spacer(minLength: 0)
                    Text(remaining)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            } else {
                Text("No rate-limit data")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helpers

    private func gaugeColor(_ pct: Double) -> Color {
        switch pct {
        case ..<30:  return .green
        case 30..<60: return .blue
        case 60..<80: return .orange
        default:      return .red
        }
    }

}


#Preview {
    DesktopWidgetView(
        usageService: UsageService(),
        statsService: StatsService(),
        sessionService: SessionService(),
        onClose: {}
    )
    .padding()
    .frame(width: 240)
}
