import Testing
@testable import ClaudeBarLib

struct ModelBreakdownTests {

    @Test func costCalculatorCostUsesAllTokenTypes() {
        let cost = CostCalculator.cost(
            modelId: "claude-opus-4-7",
            input: 100_000,
            output: 20_000,
            cacheRead: 500_000,
            cacheCreation: 40_000
        )

        // Opus 4.7: input $5, output $25, cache-read $0.50, cache-write $6.25 per MTok.
        let expected = 0.50 + 0.50 + 0.25 + 0.25
        #expect(abs(cost - expected) < 0.000_001)
    }

    @Test func displayNameDropsClaudePrefixAndCapitalizesSegments() {
        #expect(ModelBreakdown.displayName(for: "claude-opus-4-7") == "Opus 4 7")
        #expect(ModelBreakdown.displayName(for: "claude-sonnet-4-6") == "Sonnet 4 6")
        #expect(ModelBreakdown.displayName(for: "custom-model") == "Custom Model")
    }

    @Test func summariesAreSortedByCostDescending() {
        let breakdown: [String: ModelTokenBreakdown] = [
            "claude-sonnet-4-6": ModelTokenBreakdown(
                input: 1_000_000,
                output: 0,
                cacheRead: 0,
                cacheCreation: 0
            ),
            "claude-opus-4-7": ModelTokenBreakdown(
                input: 0,
                output: 1_000_000,
                cacheRead: 0,
                cacheCreation: 0
            )
        ]

        let summaries = ModelBreakdown.summaries(from: breakdown)

        #expect(summaries.map(\.model) == ["claude-opus-4-7", "claude-sonnet-4-6"])
        #expect(summaries[0].displayName == "Opus 4 7")
        #expect(abs(summaries[0].cost - 25.00) < 0.000_001)
        #expect(summaries[1].displayName == "Sonnet 4 6")
        #expect(abs(summaries[1].cost - 3.00) < 0.000_001)
    }
}
