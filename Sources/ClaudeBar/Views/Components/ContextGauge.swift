import SwiftUI

/// A compact circular gauge showing context window usage (0.0–1.0).
///
/// Color coding:
/// - < 40%  → green
/// - 40–60% → yellow
/// - 60–80% → orange
/// - > 80%  → red
struct ContextGauge: View {
    let percentage: Double  // 0.0 to 1.0
    var compact: Bool = false

    private var gaugeColor: Color {
        switch percentage {
        case ..<0.4:  return .green
        case ..<0.6:  return .yellow
        case ..<0.8:  return Color.orange
        default:      return .red
        }
    }

    private var percentLabel: String {
        "\(Int(percentage * 100))%"
    }

    var body: some View {
        if compact {
            compactView
        } else {
            fullView
        }
    }

    // MARK: - Full circular gauge

    private var fullView: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(percentage, 1.0))
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: percentage)
            Text(percentLabel)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(gaugeColor)
        }
        .frame(width: 36, height: 36)
    }

    // MARK: - Compact dot + label

    private var compactView: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(gaugeColor)
                .frame(width: 6, height: 6)
            Text(percentLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(gaugeColor)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(gaugeColor.opacity(0.1))
        .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 20) {
            ContextGauge(percentage: 0.20)
            ContextGauge(percentage: 0.50)
            ContextGauge(percentage: 0.70)
            ContextGauge(percentage: 0.90)
        }

        HStack(spacing: 12) {
            ContextGauge(percentage: 0.20, compact: true)
            ContextGauge(percentage: 0.50, compact: true)
            ContextGauge(percentage: 0.70, compact: true)
            ContextGauge(percentage: 0.90, compact: true)
        }
    }
    .padding()
    .frame(width: 300)
}
