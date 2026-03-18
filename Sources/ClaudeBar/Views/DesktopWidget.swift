import SwiftUI

struct DesktopWidgetContent: View {
    var usageService: UsageService
    var statsService: StatsService
    var sessionService: SessionService

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "brain")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("ClaudeBar")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            // Main content
            HStack(spacing: 12) {
                // 5h gauge
                if let fiveHour = usageService.usage?.fiveHour {
                    Gauge(value: min(fiveHour.utilization, 100), in: 0...100) {
                        // hidden
                    } currentValueLabel: {
                        Text("\(Int(fiveHour.utilization))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(Gradient(colors: [.green, .yellow, .orange, .red]))
                    .scaleEffect(0.7)
                    .frame(width: 40, height: 40)
                } else {
                    // No data placeholder
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Text("—")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        )
                }

                // Stats column
                VStack(alignment: .leading, spacing: 4) {
                    // Tokens today
                    HStack(spacing: 4) {
                        Image(systemName: "text.word.spacing")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        let tokens = statsService.todayTokens > 0 ? statsService.todayTokens : 0
                        Text(tokens.abbreviatedTokenCount)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }

                    // Active sessions
                    HStack(spacing: 4) {
                        Circle()
                            .fill(sessionService.activeSessions.isEmpty ? Color.secondary.opacity(0.3) : Color.green)
                            .frame(width: 6, height: 6)
                        Text("\(sessionService.activeSessions.count) session\(sessionService.activeSessions.count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundStyle(sessionService.activeSessions.isEmpty ? .secondary : .primary)
                    }

                    // Cost today
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(CostCalculator.formatCost(statsService.todayCostEstimate))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 10)

            // Time remaining
            if let remaining = usageService.usage?.fiveHour?.timeRemaining {
                Text("Resets in \(remaining)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 200, height: 160)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}
