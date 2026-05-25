import XCTest
@testable import ClaudeBarLib

final class ProviderUsageServiceOmlxTests: XCTestCase {

    // Helper : construit une ligne JSONL d'assistant avec un tool_use
    private func assistantLine(msgID: String, toolName: String) -> String {
        """
        {"type":"assistant","message":{"id":"\(msgID)","model":"claude-opus-4-7","content":[{"type":"tool_use","id":"tu_1","name":"\(toolName)","input":{"task":"do stuff"}}],"role":"assistant","usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        """
    }

    private func userLine() -> String {
        """
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}
        """
    }

    func testEmptyLinesReturnsZero() {
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([]), 0)
    }

    func testNonAssistantLineIgnored() {
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([userLine()]), 0)
    }

    func testOmlxToolCallCountedOnce() {
        let line = assistantLine(msgID: "msg_001", toolName: "mcp__omlx-delegate__delegate_to_omlx")
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([line]), 1)
    }

    func testDuplicateMessageIDDeduplicatedToOne() {
        let line = assistantLine(msgID: "msg_001", toolName: "mcp__omlx-delegate__delegate_to_omlx")
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([line, line]), 1)
    }

    func testTwoDifferentMessageIDsCountedAsTwoSeparate() {
        let line1 = assistantLine(msgID: "msg_001", toolName: "mcp__omlx-delegate__delegate_to_omlx")
        let line2 = assistantLine(msgID: "msg_002", toolName: "mcp__omlx-delegate__delegate_to_omlx")
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([line1, line2]), 2)
    }

    func testNonOmlxToolCallNotCounted() {
        let line = assistantLine(msgID: "msg_001", toolName: "mcp__codex__codex")
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([line]), 0)
    }

    func testOmlxEmbedToolAlsoCounted() {
        let line = assistantLine(msgID: "msg_001", toolName: "mcp__omlx-delegate__embed_text")
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([line]), 1)
    }

    func testMixedToolsOnlyOmlxCounted() {
        let omlxLine  = assistantLine(msgID: "msg_001", toolName: "mcp__omlx-delegate__delegate_to_omlx")
        let codexLine = assistantLine(msgID: "msg_002", toolName: "mcp__codex__codex")
        let geminiLine = assistantLine(msgID: "msg_003", toolName: "mcp__gemini-delegate__delegate_to_gemini")
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([omlxLine, codexLine, geminiLine]), 1)
    }

    func testMalformedJSONIgnored() {
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines(["not json at all", "{}"]), 0)
    }
}
