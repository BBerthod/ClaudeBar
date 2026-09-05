import SwiftUI

struct DashboardUsageSection: View {
    let usageService: UsageService

    var body: some View {
        Group {
            if usageService.usage != nil {
                usageSection
                    .padding(.horizontal, 12)
            }
            if usageService.isStale {
                usageUnavailableRow(error: usageService.lastError ?? "Usage data is out of date")
                    .padding(.horizontal, 12)
            }
        }
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

    /// Shown when the OAuth usage API returns no data, so the failure is visible
    /// instead of the 5h section silently disappearing.
    @ViewBuilder
    private func usageUnavailableRow(error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("5h usage unavailable")
                    .font(.caption)
                    .fontWeight(.medium)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
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
                let secondsRemaining = max(
                    fiveHour.resetDate?.timeIntervalSinceNow ?? .greatestFiniteMagnitude,
                    0
                )
                if let forecast = UsageForecast.limitLabel(
                    utilization: fiveHour.utilization,
                    elapsedFraction: usageService.fiveHourElapsedFraction,
                    secondsRemaining: secondsRemaining
                ) {
                    let urgent = UsageForecast.isUrgent(
                        utilization: fiveHour.utilization,
                        elapsedFraction: usageService.fiveHourElapsedFraction,
                        secondsRemaining: secondsRemaining
                    )
                    Text(forecast)
                        .font(.caption2)
                        .foregroundStyle(urgent ? .orange : .secondary)
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
}

