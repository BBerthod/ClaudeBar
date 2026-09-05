import SwiftUI

struct DashboardBurnRateCard: View {
    let burnRateService: BurnRateService
    let usageService: UsageService

    var body: some View {
        if let rate = burnRateService.burnRate {
            VStack(alignment: .leading, spacing: 4) {
                burnRateCard(rate)
                    .help("Compares today's projected cost to your 30-day average")

                // 5h window projection — only shown after 10% of the window has elapsed
                // to avoid wildly misleading projections at window start.
                if let fiveHour = usageService.usage?.fiveHour,
                   let pace = usageService.fiveHourPace,
                   usageService.fiveHourElapsedFraction >= 0.10 {
                    let projected = fiveHour.utilization / usageService.fiveHourElapsedFraction
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
                    .help("Extrapolation based on current pace — only shown after 10% of the 5h window has elapsed")
                }
            }
            .padding(.horizontal, 12)
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

    // MARK: - Helpers

    private func zoneColor(_ zone: PacingZone) -> Color {
        switch zone {
        case .chill:    return .blue
        case .onTrack:  return .green
        case .hot:      return .orange
        case .critical: return .red
        }
    }
}

