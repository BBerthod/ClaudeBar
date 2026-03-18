import Foundation
import SwiftUI

// MARK: - Date

extension Date {

    /// `true` when the date falls on today's calendar day (in the current locale).
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Common date-format tokens for use with `formatted(as:)`.
    enum DateFormatStyle {
        /// "2026-03-17"
        case iso
        /// "Mar 17, 2026"
        case medium
        /// "Monday, March 17"
        case longWeekday
        /// "17 Mar"
        case shortDayMonth
        /// "14:32"
        case time24
        /// "2:32 PM"
        case time12
    }

    /// Returns the date as a formatted string using the specified style.
    func formatted(as style: DateFormatStyle) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        switch style {
        case .iso:
            f.dateFormat = "yyyy-MM-dd"
        case .medium:
            f.dateStyle = .medium
            f.timeStyle = .none
        case .longWeekday:
            f.dateFormat = "EEEE, MMMM d"
        case .shortDayMonth:
            f.dateFormat = "d MMM"
        case .time24:
            f.dateFormat = "HH:mm"
        case .time12:
            f.timeStyle = .short
            f.dateStyle = .none
        }
        return f.string(from: self)
    }
}

// MARK: - Int (number formatting)

extension Int {

    /// Formats the integer with locale-appropriate thousands separators.
    ///
    /// Example: `1_234_567` → `"1,234,567"`
    var formattedWithSeparator: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale.current
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// Abbreviates large token counts to a compact human-readable string.
    ///
    /// - 0 ..<  1 000 → `"999"`
    /// - 1 000 ..<  1 000 000 → `"1.2K"`
    /// - ≥ 1 000 000 → `"1.2M"`
    var abbreviatedTokenCount: String {
        let value = Double(self)
        switch self {
        case ..<1_000:
            return "\(self)"
        case 1_000..<1_000_000:
            let k = value / 1_000.0
            // Show one decimal place only when it adds information.
            if k >= 10 {
                return "\(Int(k))K"
            }
            return String(format: "%.1fK", k)
        default:
            let m = value / 1_000_000.0
            if m >= 10 {
                return "\(Int(m))M"
            }
            return String(format: "%.1fM", m)
        }
    }
}

// MARK: - TimeInterval (duration formatting)

extension TimeInterval {

    /// Formats a duration as a concise human-readable string.
    ///
    /// Examples:
    /// - `45`       → `"45s"`
    /// - `3_661`    → `"1h 1m"`
    /// - `86_400`   → `"24h 0m"`
    var formattedDuration: String {
        let totalSeconds = Int(self)
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours   = totalSeconds / 3_600

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Color constants for Claude models

extension Color {

    /// Accent color associated with claude-opus-* models (purple/violet).
    static let opusColor = Color(red: 0.55, green: 0.27, blue: 0.80)

    /// Accent color associated with claude-sonnet-* models (blue).
    static let sonnetColor = Color(red: 0.20, green: 0.47, blue: 0.90)

    /// Accent color associated with claude-haiku-* models (teal/green).
    static let haikuColor = Color(red: 0.13, green: 0.70, blue: 0.56)

    /// Returns the accent color for any Claude model ID string.
    ///
    /// Falls back to `sonnetColor` for unrecognised model IDs.
    static func color(for modelId: String) -> Color {
        let lower = modelId.lowercased()
        if lower.contains("opus")   { return .opusColor }
        if lower.contains("haiku")  { return .haikuColor }
        return .sonnetColor
    }
}
