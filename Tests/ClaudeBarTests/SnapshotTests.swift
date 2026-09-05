import XCTest
import SnapshotTesting
import SwiftUI
import AppKit
@testable import ClaudeBarLib

// MARK: - Wrapper for ContributionGraph (needs @State for Binding)

private struct ContributionGraphWrapper: View {
    let dayStats: [Date: DayStats]
    @State var metric: ContributionMetric = .tokens
    var body: some View {
        ContributionGraph(dayStats: dayStats, metric: $metric)
    }
}

// MARK: - Helpers

/// Wraps a SwiftUI View in an NSHostingView sized to `size` for NSView snapshot strategy.
private func host<V: View>(_ view: V, size: CGSize) -> NSView {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    return host
}

// MARK: - SnapshotTests

@MainActor
final class SnapshotTests: XCTestCase {

    override func invokeTest() {
        withSnapshotTesting(record: .missing) {
            super.invokeTest()
        }
    }

    // MARK: - StatCard (4 tests)

    func testStatCardNormal() {
        let view = host(
            StatCard(title: "Messages", value: "142", icon: "message", trend: "+12%", trendUp: true),
            size: CGSize(width: 150, height: 80)
        )
        assertSnapshot(of: view, as: .image(perceptualPrecision: 0.98, size: CGSize(width: 150, height: 80)))
    }

    func testStatCardNoTrend() {
        let view = host(
            StatCard(title: "Sessions", value: "7", icon: "rectangle.stack"),
            size: CGSize(width: 150, height: 80)
        )
        assertSnapshot(of: view, as: .image(perceptualPrecision: 0.98, size: CGSize(width: 150, height: 80)))
    }

    func testStatCardTrendDown() {
        let view = host(
            StatCard(title: "Tool Calls", value: "89", icon: "wrench.and.screwdriver", trend: "-3%", trendUp: false),
            size: CGSize(width: 150, height: 80)
        )
        assertSnapshot(of: view, as: .image(perceptualPrecision: 0.98, size: CGSize(width: 150, height: 80)))
    }

    func testStatCardLongValue() {
        let view = host(
            StatCard(title: "Tokens", value: "1,234,567", icon: "text.word.spacing"),
            size: CGSize(width: 150, height: 80)
        )
        assertSnapshot(of: view, as: .image(perceptualPrecision: 0.98, size: CGSize(width: 150, height: 80)))
    }

    // MARK: - Sparkline (3 tests)

    func testSparklineEmpty() {
        let view = host(Sparkline(data: []), size: CGSize(width: 200, height: 50))
        assertSnapshot(of: view, as: .image(perceptualPrecision: 0.98, size: CGSize(width: 200, height: 50)))
    }

    func testSparklineRising() {
        let view = host(Sparkline(data: [1, 3, 2, 7, 5, 9, 12, 8, 15]), size: CGSize(width: 200, height: 50))
        assertSnapshot(of: view, as: .image(perceptualPrecision: 0.98, size: CGSize(width: 200, height: 50)))
    }

    func testSparklineFalling() {
        let view = host(Sparkline(data: [15, 12, 10, 8, 5, 3, 1]), size: CGSize(width: 200, height: 50))
        assertSnapshot(of: view, as: .image(perceptualPrecision: 0.98, size: CGSize(width: 200, height: 50)))
    }

    // MARK: - ContributionGraph (2 tests)

    func testContributionGraphEmpty() {
        let view = host(ContributionGraphWrapper(dayStats: [:]), size: CGSize(width: 420, height: 90))
        assertSnapshot(of: view, as: .image(perceptualPrecision: 0.98, size: CGSize(width: 420, height: 90)))
    }

    func testContributionGraphWithActivity() {
        var stats: [Date: DayStats] = [:]

        let fixedValues: [(Int, Double)] = [
            (5_000, 0.50),
            (12_000, 1.20),
            (800, 0.08),
            (30_000, 3.00),
            (7_500, 0.75),
            (22_000, 2.20),
            (1_200, 0.12),
            (45_000, 4.50),
        ]

        // Fixed anchor: Monday 6 January 2025 — prevents cell position from shifting
        // across days of the week when the test runs at different times.
        var anchorComponents = DateComponents()
        anchorComponents.year = 2025
        anchorComponents.month = 1
        anchorComponents.day = 6
        let anchor = Calendar.current.date(from: anchorComponents)!

        for (i, (tokens, cost)) in fixedValues.enumerated() {
            if let date = Calendar.current.date(byAdding: .weekOfYear, value: -i, to: anchor) {
                stats[Calendar.current.startOfDay(for: date)] = DayStats(tokens: tokens, cost: cost)
            }
        }

        let view = host(ContributionGraphWrapper(dayStats: stats), size: CGSize(width: 420, height: 90))
        assertSnapshot(of: view, as: .image(perceptualPrecision: 0.98, size: CGSize(width: 420, height: 90)))
    }
}
