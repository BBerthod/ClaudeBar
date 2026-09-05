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

}

@MainActor
final class ContributionGraphTests: XCTestCase {
    func testContributionGraphWithActivity() throws {
        let calendar = Calendar(identifier: .iso8601)
        let today = calendar.startOfDay(for: Date())
        let values: [(Int, Double, Color, Color)] = [
            (0, 0, .primary.opacity(0.06), .primary.opacity(0.06)),
            (25, 10, .blue.opacity(0.4), .green.opacity(0.2)),
            (50, 33, .blue.opacity(0.6), .orange.opacity(0.33)),
            (75, 66, .blue.opacity(0.8), .red.opacity(0.66)),
            (100, 100, .blue.opacity(1), .red.opacity(1)),
        ]
        let dates = try values.indices.map {
            try XCTUnwrap(calendar.date(byAdding: .day, value: -$0, to: today))
        }
        let stats = Dictionary(uniqueKeysWithValues: zip(dates, values).map {
            ($0.0, DayStats(tokens: $0.1.0, cost: $0.1.1))
        })
        for (date, value) in zip(dates, values) {
            let noon = try XCTUnwrap(calendar.date(byAdding: .hour, value: 12, to: date))
            XCTAssertEqual(ContributionGraph.cellColor(for: noon, dayStats: stats, metric: .tokens), value.2)
            XCTAssertEqual(ContributionGraph.cellColor(for: noon, dayStats: stats, metric: .cost), value.3)
        }
        let missing = try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: today))
        for metric in ContributionMetric.allCases {
            XCTAssertEqual(ContributionGraph.cellColor(for: missing, dayStats: stats, metric: metric),
                           Color.primary.opacity(0.06))
        }
    }
}
