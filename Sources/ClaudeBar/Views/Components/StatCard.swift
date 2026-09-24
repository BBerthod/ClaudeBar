import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var trend: String? = nil
    var trendUp: Bool = true

    var body: some View {
        let trendColor = Theme.color(trendUp ? .ok : .critical)

        VStack(alignment: .leading, spacing: Theme.Space.xs + 2) {
            HStack {
                Image(systemName: icon)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let trend {
                    Text(trend)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(trendColor)
                        .padding(.horizontal, Theme.Space.xs)
                        .padding(.vertical, 2)
                        .background(trendColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Text(value)
                .font(Theme.Font.metric)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
        StatCard(title: "Messages", value: "142", icon: "message", trend: "+12%", trendUp: true)
        StatCard(title: "Sessions", value: "7", icon: "rectangle.stack")
        StatCard(title: "Tool Calls", value: "89", icon: "wrench.and.screwdriver", trend: "-3%", trendUp: false)
        StatCard(title: "Tokens", value: "1.2M", icon: "text.word.spacing")
    }
    .padding()
    .frame(width: 300)
}
