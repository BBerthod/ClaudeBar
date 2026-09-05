import XCTest
@testable import ClaudeBarLib

final class ModelCatalogSnapshotTests: XCTestCase {
    func testBundledSnapshotDecodesAndKnowsCurrentModels() throws {
        let catalog = try ModelCatalog.bundled()
        for id in ["claude-opus-5", "claude-sonnet-5", "claude-fable-5-1", "claude-opus-4-8", "claude-haiku-4-5",
                   "claude-sonnet-4-6", "claude-3-7-sonnet", "gpt-6-astra", "gpt-5.6-sol", "gemini-3.5-flash"] {
            XCTAssertNotNil(catalog.entries[id], id)
        }
        XCTAssertEqual(catalog.entries["claude-sonnet-5"]?.inputPerMTok, 2)
        XCTAssertGreaterThan(catalog.entries.count, 50)
    }
}
