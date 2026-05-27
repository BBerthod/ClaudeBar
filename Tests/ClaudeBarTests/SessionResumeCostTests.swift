import Testing
@testable import ClaudeBarLib

struct SessionResumeCostTests {

    @Test func testContextInfoReturnsTokensModelAndFraction() {
        let lines = [
            #"{"type":"assistant","message":{"model":"claude-opus-4-7","usage":{"input_tokens":10,"cache_read_input_tokens":490000,"cache_creation_input_tokens":500}}}"#
        ]

        let info = SessionService.contextInfo(fromLines: lines)

        #expect(info.tokens == 490_510)
        #expect(info.model == "claude-opus-4-7")
        #expect(abs(info.fraction - 0.49051) < 0.001)
    }

    @Test func testContextInfoEmptyLinesReturnZeroValues() {
        let info = SessionService.contextInfo(fromLines: [])

        #expect(info.tokens == 0)
        #expect(info.model == "")
        #expect(info.fraction == 0)
    }

    @Test func testResumeCostUsesCacheReadPricing() {
        let cost = CostCalculator.cost(
            modelId: "claude-opus-4-7",
            input: 0,
            output: 0,
            cacheRead: 490_000,
            cacheCreation: 0
        )

        #expect(abs(cost - 0.245) < 0.001)
    }
}
