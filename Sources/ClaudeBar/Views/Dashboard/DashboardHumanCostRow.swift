import SwiftUI

struct DashboardHumanCostRow: View {
    let effectiveMessages: Int
    let effectiveToolCalls: Int
    let effectiveCost: Double

    var body: some View {
        if effectiveCost > 0 && effectiveMessages > 0 {
            humanCostRow
                .padding(.horizontal, 12)
        }
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
}

