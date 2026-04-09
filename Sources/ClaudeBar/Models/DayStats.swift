import Foundation

struct DayStats: Sendable {
    var tokens: Int    // input + output + cacheRead + cacheWrite
    var cost: Double   // estimated USD
}
