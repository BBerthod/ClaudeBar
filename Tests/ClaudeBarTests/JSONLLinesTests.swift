import XCTest
@testable import ClaudeBarLib

final class JSONLLinesTests: XCTestCase {

    private let assistantNeedle = "\"assistant\""

    private func strings(_ lines: [Data]) -> [String] {
        lines.map { String(decoding: $0, as: UTF8.self) }
    }

    func testKeepsOnlyLinesContainingNeedle() {
        let data = Data("{\"type\":\"user\"}\n{\"type\":\"assistant\",\"x\":1}\n{\"type\":\"tool_result\"}\n".utf8)

        XCTAssertEqual(
            strings(JSONLLines.lines(in: data, containing: assistantNeedle)),
            ["{\"type\":\"assistant\",\"x\":1}"]
        )
    }

    func testKeepsSpacedJSON() {
        let data = Data("{\"type\": \"assistant\"}\n".utf8)

        XCTAssertEqual(JSONLLines.lines(in: data, containing: assistantNeedle).count, 1)
    }

    func testLastLineWithoutTrailingNewlineIsIncluded() {
        let data = Data("a\n{\"type\":\"assistant\"}".utf8)

        XCTAssertEqual(JSONLLines.lines(in: data, containing: assistantNeedle).count, 1)
    }

    func testSkipsEmptyLines() {
        let data = Data("\n\n{\"type\":\"assistant\"}\n\n".utf8)

        XCTAssertEqual(JSONLLines.lines(in: data, containing: assistantNeedle).count, 1)
    }

    func testEmptyDataReturnsNoLines() {
        XCTAssertEqual(JSONLLines.lines(in: Data(), containing: assistantNeedle), [])
    }

    func testNeedleAbsentReturnsNoLines() {
        let data = Data("{\"type\":\"user\"}\n{\"type\":\"tool_result\"}\n".utf8)

        XCTAssertEqual(JSONLLines.lines(in: data, containing: assistantNeedle), [])
    }

    func testEmptyNeedleReturnsAllNonEmptyLines() {
        let data = Data("a\n\nb\n".utf8)

        XCTAssertEqual(strings(JSONLLines.lines(in: data, containing: "")), ["a", "b"])
    }

    func testPreservesOrder() {
        let data = Data("{\"type\":\"assistant\",\"n\":1}\n{\"type\":\"assistant\",\"n\":2}\n{\"type\":\"assistant\",\"n\":3}\n".utf8)

        XCTAssertEqual(
            strings(JSONLLines.lines(in: data, containing: assistantNeedle)),
            [
                "{\"type\":\"assistant\",\"n\":1}",
                "{\"type\":\"assistant\",\"n\":2}",
                "{\"type\":\"assistant\",\"n\":3}",
            ]
        )
    }
}
