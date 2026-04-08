import SwiftUI

/// A 4x6 grid of colored cells representing 24 hours (0-23).
/// Color intensity is based on message count for each hour.
struct HourGridView: View {
    let data: [(hour: Int, count: Int)]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)

    private var maxCount: Int {
        data.map(\.count).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(data, id: \.hour) { point in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(cellColor(for: point.count))
                        .frame(height: 32)
                        .overlay {
                            Text("\(point.hour)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(textColor(for: point.count))
                        }
                        .help("\(point.hour):00 \u{2014} \(point.count) messages")
                }
            }

            // Legend row
            HStack(spacing: 6) {
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(legendColor(for: level))
                        .frame(width: 14, height: 14)
                }
                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Color helpers

    private func cellColor(for count: Int) -> Color {
        guard maxCount > 0, count > 0 else {
            return .primary.opacity(0.05)
        }
        let intensity = Double(count) / Double(maxCount)
        switch intensity {
        case ..<0.25:  return .blue.opacity(0.35)
        case ..<0.50:  return .blue.opacity(0.65)
        case ..<0.75:  return .purple.opacity(0.70)
        default:       return .red.opacity(0.80)
        }
    }

    private func textColor(for count: Int) -> Color {
        guard maxCount > 0, count > 0 else {
            return .secondary
        }
        let intensity = Double(count) / Double(maxCount)
        return intensity >= 0.50 ? .white : .primary
    }

    private func legendColor(for level: Int) -> Color {
        switch level {
        case 0:  return .primary.opacity(0.05)
        case 1:  return .blue.opacity(0.35)
        case 2:  return .blue.opacity(0.65)
        case 3:  return .purple.opacity(0.70)
        default: return .red.opacity(0.80)
        }
    }
}

#Preview {
    let sampleData = (0..<24).map { hour in
        (hour: hour, count: [0, 2, 5, 12, 8, 0, 1, 15, 20, 30, 45, 60,
                             55, 40, 35, 28, 22, 18, 14, 10, 6, 3, 1, 0][hour])
    }
    return HourGridView(data: sampleData)
        .padding()
        .frame(width: 300)
}
