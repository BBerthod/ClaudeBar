import Foundation

@Observable
@MainActor
final class BurnRateService {
    private(set) var burnRate: BurnRate?

    /// Call this when stats update to recalculate burn rate.
    /// Falls back to `liveStatsService` when stats-cache has no entry for today.
    func update(statsService: StatsService, liveStatsService: LiveStatsService? = nil) {
        guard let stats = statsService.stats else {
            burnRate = nil
            return
        }

        // 1. Calculate hours active today
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let minuteInHour = calendar.component(.minute, from: now)
        let hoursActive = max(Double(currentHour) + Double(minuteInHour) / 60.0, 1.0)

        // 2. Calculate current rates (prefer stats-cache, fallback to live JSONL)
        let todayTokens = statsService.todayTokens > 0
            ? statsService.todayTokens
            : (liveStatsService?.todayTokens ?? 0)
        let todayMessages = statsService.todayMessages > 0
            ? statsService.todayMessages
            : (liveStatsService?.todayMessages ?? 0)
        let todayCost = statsService.todayCostEstimate > 0
            ? statsService.todayCostEstimate
            : (liveStatsService?.todayCost ?? 0)

        let tokensPerHour = Double(todayTokens) / hoursActive
        let messagesPerHour = Double(todayMessages) / hoursActive
        let costPerHour = todayCost / hoursActive

        // 3. Project to end of day (assume 10 active hours as typical workday)
        let typicalWorkHours = 10.0
        let remainingHours = max(typicalWorkHours - hoursActive, 0)
        let projectedDailyTokens = todayTokens + Int(tokensPerHour * remainingHours)
        let projectedDailyCost = todayCost + costPerHour * remainingHours

        // 4. Calculate averages from the last 30 days (excluding today)
        let last30 = stats.last30DaysActivity
        let last30Tokens = stats.last30DaysModelTokens

        let avgTokens: Double
        let avgCost: Double

        if last30.count > 1 {
            // Exclude today from averages
            let previousDays = Array(last30.dropLast())
            let previousTokenDays = Array(last30Tokens.dropLast())

            let totalPrevTokens = previousTokenDays.reduce(0) { sum, day in
                sum + day.tokensByModel.values.reduce(0, +)
            }
            avgTokens = previousTokenDays.isEmpty ? 0 : Double(totalPrevTokens) / Double(previousTokenDays.count)

            // Rough cost estimate: scale total cost by this day-average's proportion
            let allTimeTokens = stats.dailyModelTokens.reduce(0) { sum, day in
                sum + day.tokensByModel.values.reduce(0, +)
            }
            avgCost = allTimeTokens > 0 && avgTokens > 0
                ? statsService.totalCostEstimate * (avgTokens / Double(allTimeTokens))
                : 0

            _ = previousDays // silence unused-variable warning; avgMessages not used in BurnRate init
        } else {
            avgTokens = Double(todayTokens)
            avgCost = todayCost
        }

        // 5. Determine pacing zone based on projected vs average daily tokens
        let percentOfAvg = avgTokens > 0 ? Double(projectedDailyTokens) / avgTokens : 1.0
        let zone: PacingZone
        switch percentOfAvg {
        case ..<0.7:        zone = .chill
        case 0.7..<1.3:    zone = .onTrack
        case 1.3..<2.0:    zone = .hot
        default:            zone = .critical
        }

        burnRate = BurnRate(
            tokensPerHour: tokensPerHour,
            messagesPerHour: messagesPerHour,
            costPerHour: costPerHour,
            projectedDailyTokens: projectedDailyTokens,
            projectedDailyCost: projectedDailyCost,
            zone: zone,
            hoursActive: hoursActive,
            averageDailyTokens: Int(avgTokens),
            averageDailyCost: avgCost,
            percentOfAverage: percentOfAvg
        )
    }
}
