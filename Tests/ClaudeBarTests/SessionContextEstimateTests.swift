import Testing
@testable import ClaudeBarLib

struct SessionContextEstimateTests {

    @Test func testOpusSessionUsesOneMillionContextWindow() {
        let lines = [
            #"{"type":"assistant","message":{"model":"claude-opus-4-7","usage":{"input_tokens":10,"cache_read_input_tokens":490000,"cache_creation_input_tokens":10488}}}"#
        ]

        let fraction = SessionService.contextFraction(fromLines: lines)

        #expect(abs(fraction - 0.5005) < 0.001)
    }

    @Test func testSonnetSessionUsesOneMillionContextWindow() {
        let lines = [
            #"{"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":195,"cache_read_input_tokens":70000,"cache_creation_input_tokens":3000}}}"#
        ]

        let fraction = SessionService.contextFraction(fromLines: lines)

        #expect(abs(fraction - 0.0732) < 0.001)
    }

    @Test func testLastAssistantMessageWins() {
        let lines = [
            #"{"type":"assistant","message":{"model":"claude-opus-4-7","usage":{"input_tokens":900000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-4-7","usage":{"input_tokens":100000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        ]

        let fraction = SessionService.contextFraction(fromLines: lines)

        #expect(abs(fraction - 0.1) < 0.001)
    }

    @Test func testPartialAndNonAssistantLinesAreSkipped() {
        let lines = [
            "{partial broken json",
            #"{"type":"user","message":{"role":"user","content":"hello"}}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-4-7","usage":{"input_tokens":250000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        ]

        let fraction = SessionService.contextFraction(fromLines: lines)

        #expect(abs(fraction - 0.25) < 0.001)
    }

    @Test func testEmptyAndNoUsageLinesReturnZero() {
        #expect(SessionService.contextFraction(fromLines: []) == 0)

        let lines = [
            #"{"type":"user","message":{"role":"user","content":"hello"}}"#,
            #"{"type":"user","message":{"role":"user","content":"again"}}"#
        ]

        #expect(SessionService.contextFraction(fromLines: lines) == 0)
    }

    @Test func testContextFractionClampsAtOne() {
        let lines = [
            #"{"type":"assistant","message":{"model":"claude-opus-4-7","usage":{"input_tokens":1200000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        ]

        let fraction = SessionService.contextFraction(fromLines: lines)

        #expect(fraction == 1.0)
    }

    @Test func testContextWindowForModel() {
        #expect(SessionService.contextWindow(forModel: "claude-opus-4-7") == 1_000_000)
        #expect(SessionService.contextWindow(forModel: "claude-sonnet-4-6") == 1_000_000)
        #expect(SessionService.contextWindow(forModel: "claude-3-5-haiku") == 200_000)
        #expect(SessionService.contextWindow(forModel: "") == 200_000)
    }
}
