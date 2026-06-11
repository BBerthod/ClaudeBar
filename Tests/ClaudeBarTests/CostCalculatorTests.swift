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

    // MARK: - New tests

    func testPricingFable5ExactMatch() {
        let p = CostCalculator.pricing(for: "claude-fable-5")
        XCTAssertEqual(p.inputPerMTok, 10.00)
        XCTAssertEqual(p.outputPerMTok, 50.00)
        XCTAssertEqual(p.cacheReadPerMTok, 1.00)
        XCTAssertEqual(p.cacheWritePerMTok, 12.50)
    }

    func testPricingPartialMatchFable() {
        let p = CostCalculator.pricing(for: "claude-fable-future")
        XCTAssertEqual(p.inputPerMTok, 10.00)
    }

    func testPricingPartialMatchMythos() {
        // Mythos 5 shares Fable 5 pricing
        let p = CostCalculator.pricing(for: "claude-mythos-5")
        XCTAssertEqual(p.inputPerMTok, 10.00)
        XCTAssertEqual(p.outputPerMTok, 50.00)
    }

    func testPricingOpus48ExactMatch() {
        let p = CostCalculator.pricing(for: "claude-opus-4-8")
        XCTAssertEqual(p.inputPerMTok, 5.00)
        XCTAssertEqual(p.outputPerMTok, 25.00)
        XCTAssertEqual(p.cacheReadPerMTok, 0.50)
        XCTAssertEqual(p.cacheWritePerMTok, 6.25)
    }

    func testPricingOpus47ExactMatch() {
        let p = CostCalculator.pricing(for: "claude-opus-4-7")
        XCTAssertEqual(p.inputPerMTok, 5.00)
        XCTAssertEqual(p.outputPerMTok, 25.00)
        XCTAssertEqual(p.cacheReadPerMTok, 0.50)
        XCTAssertEqual(p.cacheWritePerMTok, 6.25)
    }

    func testPricingHaikuCacheFields() {
        let p = CostCalculator.pricing(for: "claude-haiku-4-5-20251001")
        XCTAssertEqual(p.cacheReadPerMTok, 0.10)
        XCTAssertEqual(p.cacheWritePerMTok, 1.25)
    }

    func testPricingFallbackToOpusPinned() {
        let p = CostCalculator.pricing(for: "some-unknown-model-xyz")
        XCTAssertEqual(p.inputPerMTok, 5.00)
        XCTAssertEqual(p.outputPerMTok, 25.00)
    }

    func testEstimateDailyCostWithCacheTokens() {
        let tokens = ["claude-opus-4-6": 100_000]
        // fraction = 100_000 / (200_000 + 50_000) = 0.4
        // input  = 200_000 * 0.4 / 1e6 * 5.00  = 0.40
        // output =  50_000 * 0.4 / 1e6 * 25.00 = 0.50
        // read   = 400_000 * 0.4 / 1e6 * 0.50  = 0.08
        // write  = 100_000 * 0.4 / 1e6 * 6.25  = 0.25
        // total  = 1.23
        let entry = ModelUsageEntry(
            inputTokens: 200_000,
            outputTokens: 50_000,
            cacheReadInputTokens: 400_000,
            cacheCreationInputTokens: 100_000,
            webSearchRequests: 0,
            costUSD: 0,
            contextWindow: 200_000,
            maxOutputTokens: 8192
        )
        let cost = CostCalculator.estimateDailyCost(
            tokens: tokens,
            modelUsage: ["claude-opus-4-6": entry]
        )
        XCTAssertEqual(cost, 1.23, accuracy: 0.001)
    }
}
