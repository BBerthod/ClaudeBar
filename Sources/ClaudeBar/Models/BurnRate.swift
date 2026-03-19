import Foundation

enum PacingZone: String, Sendable {
    case chill = "Chill"        // well under typical usage
    case onTrack = "On Track"   // normal pace
    case hot = "Hot"            // above average, will exceed if continued
    case critical = "Critical"  // significantly above normal
}

struct BurnRate: Sendable {
    let tokensPerHour: Double
    let messagesPerHour: Double
    let costPerHour: Double
    let projectedDailyTokens: Int
    let projectedDailyCost: Double
    let zone: PacingZone
    let hoursActive: Double           // hours since first activity today
    let averageDailyTokens: Int       // average from last 30 days
    let averageDailyCost: Double
    let percentOfAverage: Double      // current / average (e.g. 1.5 = 150%)

    /// Formatted projected cost
    var projectedCostFormatted: String {
        CostCalculator.formatCost(projectedDailyCost)
    }

    /// Formatted current burn rate
    var costPerHourFormatted: String {
        CostCalculator.formatCost(costPerHour) + "/hr"
    }
}
