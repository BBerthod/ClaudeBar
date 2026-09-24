import AppKit
import SwiftUI

// MARK: - Theme

/// Design tokens shared by every view: spacing, radii, status colors and type roles.
enum Theme {

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    enum Radius {
        static let card: CGFloat = 12
        static let chip: CGFloat = 6
    }

    /// Severity of a status, from calm to alarming. `.neutral` = unknown / not applicable.
    ///
    /// Views keep their own business thresholds and only map the resulting state to a level.
    enum Level: CaseIterable {
        case neutral, ok, info, warn, high, critical
    }

    /// Muted, warm status palette (no system green/red). Dynamic for light and dark appearance.
    static func color(_ level: Level) -> Color {
        switch level {
        case .neutral:  return .secondary
        case .ok:       return dynamic(light: (0.20, 0.48, 0.31), dark: (0.45, 0.75, 0.55))  // sage
        case .info:     return dynamic(light: (0.24, 0.38, 0.58), dark: (0.55, 0.68, 0.88))  // slate blue
        case .warn:     return dynamic(light: (0.60, 0.40, 0.04), dark: (0.90, 0.72, 0.30))  // ochre
        case .high:     return dynamic(light: (0.74, 0.32, 0.14), dark: (0.95, 0.58, 0.38))  // terracotta
        case .critical: return dynamic(light: (0.70, 0.18, 0.18), dark: (0.95, 0.45, 0.42))  // brick
        }
    }

    // Contrast ratios measured against white (light) and #1e1e1e (dark):
    // ok 5.2 / 7.6 · info 6.3 / 7.3 · warn 4.9 / 9.0 · high 4.8 / 7.3 · critical 6.3 / 5.9.
    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// Type roles. `metric` is for numbers (rounded, tabular digits so values don't jitter).
    enum Font {
        static let metric = SwiftUI.Font.system(.headline, design: .rounded).weight(.bold).monospacedDigit()
        /// Section titles — callers add `.textCase(.uppercase)` and `.tracking(0.6)`.
        static let label = SwiftUI.Font.system(.caption2).weight(.semibold)
        static let caption = SwiftUI.Font.system(.caption)
    }
}
