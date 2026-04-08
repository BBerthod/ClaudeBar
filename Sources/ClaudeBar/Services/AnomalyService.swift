import Foundation

/// Detects when daily spend is unusually high compared to the 30-day baseline.
/// Fires a one-shot notification per day when cost exceeds 2x the average.
@Observable
@MainActor
final class AnomalyService {
    private(set) var lastAnomalyDate: String?

    private enum DefaultsKey {
        static let lastAnomalyDate = "claudebar.lastAnomalyDate"
    }

    init() {
        lastAnomalyDate = UserDefaults.standard.string(forKey: DefaultsKey.lastAnomalyDate)
    }

    /// Call this from the 30s refresh timer.
    func check(burnRateService: BurnRateService, notificationService: NotificationService) {
        guard let burnRate = burnRateService.burnRate else { return }
        guard burnRate.percentOfAverage >= 2.0 else { return }

        // Only fire once per day
        let today = DateFormatter.isoDate.string(from: Date())
        guard lastAnomalyDate != today else { return }

        lastAnomalyDate = today
        UserDefaults.standard.set(today, forKey: DefaultsKey.lastAnomalyDate)

        let factor = Int(burnRate.percentOfAverage)
        notificationService.sendCostAnomalyAlert(
            projectedCost: burnRate.projectedDailyCost,
            averageCost: burnRate.averageDailyCost,
            factor: factor
        )
    }
}
