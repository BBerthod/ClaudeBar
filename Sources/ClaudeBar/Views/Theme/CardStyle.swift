import SwiftUI

/// Standard card surface: material fill, rounded corners and a hairline border.
struct CardStyle: ViewModifier {
    var padding: CGFloat = Theme.Space.m

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}

extension View {
    func card(padding: CGFloat = Theme.Space.m) -> some View {
        modifier(CardStyle(padding: padding))
    }
}
