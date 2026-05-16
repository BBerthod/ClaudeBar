import XCTest
@testable import ClaudeBarLib

@MainActor
final class StatsServiceDisplayNameTests: XCTestCase {

    func testOpus46() {
        XCTAssertEqual(StatsService.displayName(for: "claude-opus-4-6"), "Opus 4.6")
    }

    func testSonnetWithDateSuffix() {
        XCTAssertEqual(StatsService.displayName(for: "claude-sonnet-4-5-20250929"), "Sonnet 4.5")
    }

    func testHaikuWithDateSuffix() {
        XCTAssertEqual(StatsService.displayName(for: "claude-haiku-4-5-20251001"), "Haiku 4.5")
    }

    func testOpusWithDateSuffix() {
        XCTAssertEqual(StatsService.displayName(for: "claude-opus-4-5-20251101"), "Opus 4.5")
    }

    func testUnknownModelPassthrough() {
        XCTAssertEqual(StatsService.displayName(for: "unknown-model-xyz"), "unknown-model-xyz")
    }

    func testFamilyOnlyWithoutVersion() {
        // If only family name is present and no version parts follow, returns just the family name
        XCTAssertEqual(StatsService.displayName(for: "claude-opus"), "Opus")
    }

    func testOpus47() {
        XCTAssertEqual(StatsService.displayName(for: "claude-opus-4-7"), "Opus 4.7")
    }
}
