import SwiftUI

struct TokenBar: View {
    let segments: [(model: String, tokens: Int)]

    private var total: Int {
        segments.reduce(0) { $0 + $1.tokens }
    }

    var body: some View {
        GeometryReader { geometry in
            if total == 0 {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
            } else {
                HStack(spacing: 2) {
                    ForEach(segments.indices, id: \.self) { idx in
                        let segment = segments[idx]
                        let fraction = Double(segment.tokens) / Double(total)
                        let width = geometry.size.width * fraction

                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorForModel(segment.model))
                            .frame(width: max(width - 2, 0))
                            .overlay {
                                if width > 28 {
                                    Text(abbreviate(segment.tokens))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                            }
                    }
                }
            }
        }
    }

    private func colorForModel(_ modelId: String) -> Color {
        let name = StatsService.displayName(for: modelId).lowercased()
        if name.contains("opus")   { return .opusColor }
        if name.contains("sonnet") { return .sonnetColor }
        if name.contains("haiku")  { return .haikuColor }
        return Color.accentColor
    }

    private func abbreviate(_ tokens: Int) -> String {
        tokens.abbreviatedTokenCount
    }
}

#Preview {
    VStack(spacing: 12) {
        TokenBar(segments: [
            (model: "claude-opus-4-5", tokens: 50_000),
            (model: "claude-sonnet-4-5", tokens: 200_000),
            (model: "claude-haiku-4-5", tokens: 80_000),
        ])
        .frame(height: 28)

        TokenBar(segments: [
            (model: "claude-sonnet-4-5", tokens: 300_000),
        ])
        .frame(height: 28)

        TokenBar(segments: [])
            .frame(height: 28)
    }
    .padding()
    .frame(width: 360)
}
