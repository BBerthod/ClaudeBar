import XCTest
@testable import ClaudeBarLib

final class CostCalculatorTests: XCTestCase {

    // MARK: - formatCost

    func testFormatCostZero() {
        XCTAssertEqual(CostCalculator.formatCost(0), "$0.00")
    }

    func testFormatCostPositive() {
        XCTAssertEqual(CostCalculator.formatCost(12.345), "$12.35")
        XCTAssertEqual(CostCalculator.formatCost(0.001), "$0.00")
        XCTAssertEqual(CostCalculator.formatCost(100), "$100.00")
    }

    // MARK: - pricing(for:)

    func testPricingExactMatch() {
        let opus = CostCalculator.pricing(for: "claude-opus-4-6")
        XCTAssertEqual(opus.inputPerMTok, 5.00)
        XCTAssertEqual(opus.outputPerMTok, 25.00)

        let haiku = CostCalculator.pricing(for: "claude-haiku-4-5-20251001")
        XCTAssertEqual(haiku.inputPerMTok, 1.00)
        XCTAssertEqual(haiku.outputPerMTok, 5.00)
    }

    func testPricingPartialMatchHaiku() {
        let p = CostCalculator.pricing(for: "claude-haiku-unknown-version")
        XCTAssertEqual(p.inputPerMTok, 1.00)
    }

    func testPricingPartialMatchSonnet() {
        let p = CostCalculator.pricing(for: "claude-sonnet-future")
        XCTAssertEqual(p.inputPerMTok, 3.00)
    }

    func testPricingFallbackToOpus() {
        let unknown = CostCalculator.pricing(for: "some-unknown-model")
        let opus = CostCalculator.pricing(for: "claude-opus-4-6")
        XCTAssertEqual(unknown.inputPerMTok, opus.inputPerMTok)
        XCTAssertEqual(unknown.outputPerMTok, opus.outputPerMTok)
    }

    // MARK: - estimateDailyCost

    func testEstimateDailyCostEmptyTokens() {
        let cost = CostCalculator.estimateDailyCost(tokens: [:], modelUsage: [:])
        XCTAssertEqual(cost, 0.0)
    }

    func testEstimateDailyCostNoModelUsage() {
        // Without cumulative model usage, falls back to input-only pricing
        let tokens = ["claude-haiku-4-5-20251001": 1_000_000]
        let cost = CostCalculator.estimateDailyCost(tokens: tokens, modelUsage: [:])
        // 1M tokens at $1.00/MTok = $1.00
        XCTAssertEqual(cost, 1.00, accuracy: 0.001)
    }

    func testEstimateDailyCostWithModelUsage() {
        let tokens = ["claude-opus-4-6": 100_000]
        let entry = ModelUsageEntry(
            inputTokens: 200_000,
            outputTokens: 50_000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            webSearchRequests: 0,
            costUSD: 0,
            contextWindow: 200_000,
            maxOutputTokens: 8192
        )
        let usage: [String: ModelUsageEntry] = ["claude-opus-4-6": entry]
        let cost = CostCalculator.estimateDailyCost(tokens: tokens, modelUsage: usage)
        // fraction = 100_000 / 250_000 = 0.4
        // input = 200_000 * 0.4 / 1M * 5 = 0.4
        // output = 50_000 * 0.4 / 1M * 25 = 0.5
        XCTAssertEqual(cost, 0.9, accuracy: 0.001)
    }
}
