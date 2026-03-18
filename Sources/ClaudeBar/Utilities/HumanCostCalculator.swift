import Foundation

/// Estimates the equivalent human developer cost for work performed by Claude.
///
/// Hypothesis: 1 Claude message ≈ 2 minutes of human dev work, accounting for
/// research, writing, and debugging. Tool calls add 0.5 minutes each, representing
/// the overhead of complex operations (file edits, searches, compilations).
///
/// Default hourly rate: $80/h (mid-level developer, US market).
enum HumanCostCalculator {

    // MARK: - Constants

    /// Minutes of human work equivalent per Claude message.
    static let minutesPerMessage: Double = 2.0

    /// Additional minutes per tool call (file edit, search, shell command, etc.).
    static let minutesPerToolCall: Double = 0.5

    /// Default hourly rate in USD used when no rate is specified.
    static let defaultHourlyRate: Double = 80.0

    // MARK: - Estimation

    /// Estimates the equivalent human hours for a given number of messages and tool calls.
    ///
    /// - Parameters:
    ///   - messages: Total number of Claude messages in the session or period.
    ///   - toolCalls: Total number of tool calls (file reads, edits, searches, etc.).
    /// - Returns: Estimated human work in hours.
    static func estimateHumanHours(messages: Int, toolCalls: Int) -> Double {
        let totalMinutes = Double(messages) * minutesPerMessage
                         + Double(toolCalls) * minutesPerToolCall
        return totalMinutes / 60.0
    }

    /// Estimates the equivalent human cost in USD for a given number of messages and tool calls.
    ///
    /// - Parameters:
    ///   - messages: Total number of Claude messages in the session or period.
    ///   - toolCalls: Total number of tool calls (file reads, edits, searches, etc.).
    ///   - hourlyRate: Hourly developer rate in USD. Defaults to `$80/h`.
    /// - Returns: Estimated human cost in USD.
    static func estimateHumanCost(
        messages: Int,
        toolCalls: Int,
        hourlyRate: Double = defaultHourlyRate
    ) -> Double {
        let hours = estimateHumanHours(messages: messages, toolCalls: toolCalls)
        return hours * hourlyRate
    }

    // MARK: - ROI

    /// Computes the ROI multiplier: how many times cheaper Claude is than an equivalent human.
    ///
    /// A value of 10 means Claude performed the work at 1/10th of the human cost.
    ///
    /// - Parameters:
    ///   - humanCost: Estimated human equivalent cost in USD.
    ///   - claudeCost: Actual Claude API cost in USD.
    /// - Returns: `humanCost / claudeCost`, or `0` if `claudeCost` is zero.
    static func roiMultiplier(humanCost: Double, claudeCost: Double) -> Double {
        guard claudeCost > 0 else { return 0 }
        return humanCost / claudeCost
    }

    // MARK: - Formatting

    /// Formats a duration in hours into a human-readable string.
    ///
    /// - Less than 1 hour: `"Xm"` (e.g. `"45m"`)
    /// - 1 hour or more: `"Xh Ym"` (e.g. `"2h 15m"`)
    /// - 24 hours or more: `"Xd Yh"` (e.g. `"1d 3h"`)
    ///
    /// - Parameter hours: Duration in hours (may be fractional).
    /// - Returns: Formatted string representation.
    static func formatHours(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())

        if hours >= 24 {
            let days  = totalMinutes / (60 * 24)
            let remaining = (totalMinutes % (60 * 24)) / 60
            return "\(days)d \(remaining)h"
        } else if hours >= 1 {
            let wholeHours = totalMinutes / 60
            let minutes    = totalMinutes % 60
            return "\(wholeHours)h \(minutes)m"
        } else {
            return "\(totalMinutes)m"
        }
    }
}
