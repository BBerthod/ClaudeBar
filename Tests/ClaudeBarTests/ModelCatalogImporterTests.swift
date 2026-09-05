import XCTest
@testable import ClaudeBarLib

final class ModelCatalogImporterTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "litellm-sample", withExtension: "json", subdirectory: "Fixtures"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testImportsTargetProvidersOnly() throws {
        let catalog = try ModelCatalogImporter.normalise(litellm: fixture(), generatedAt: Date())
        XCTAssertNotNil(catalog.entries["claude-opus-5"])
        XCTAssertNotNil(catalog.entries["gpt-6-astra"])
        XCTAssertNotNil(catalog.entries["gemini-3.5-flash"])
        XCTAssertNil(catalog.entries["sample_spec"])
        XCTAssertTrue(catalog.entries.keys.allSatisfy { !$0.hasPrefix("ollama/") && !$0.hasPrefix("mistral/") && !$0.hasPrefix("groq/") })
    }

    func testCloudPrefixedDuplicatesCollapse() throws {
        let catalog = try ModelCatalogImporter.normalise(litellm: fixture(), generatedAt: Date())
        XCTAssertNil(catalog.entries["us.anthropic.claude-opus-5"])
        XCTAssertNil(catalog.entries["azure/gpt-5.6-sol"])
        XCTAssertEqual(catalog.entries["claude-opus-5"]?.inputPerMTok, 5)
    }

    func testPricesAreConvertedToPerMillion() throws {
        let e = try XCTUnwrap(ModelCatalogImporter.normalise(litellm: fixture(), generatedAt: Date()).entries["claude-fable-5-1"])
        XCTAssertEqual(e.inputPerMTok, 10, accuracy: 1e-9)
        XCTAssertEqual(e.outputPerMTok, 50, accuracy: 1e-9)
        XCTAssertEqual(e.cacheReadPerMTok, 0.25, accuracy: 1e-9)
        XCTAssertEqual(e.cacheWritePerMTok, 12.5, accuracy: 1e-9)
        XCTAssertEqual(e.contextWindow, 1_000_000)
        XCTAssertEqual(e.family, "fable"); XCTAssertEqual(e.provider, "anthropic")
    }

    func testMissingCachePricesAreDerived() throws {
        // fixture entry "claude-test-no-cache": input 4e-6, output 2e-5, no cache fields
        let e = try XCTUnwrap(ModelCatalogImporter.normalise(litellm: fixture(), generatedAt: Date()).entries["claude-test-no-cache"])
        XCTAssertEqual(e.cacheReadPerMTok, 0.4, accuracy: 1e-9)   // 10 % of input
        XCTAssertEqual(e.cacheWritePerMTok, 5.0, accuracy: 1e-9)  // 125 % of input
    }

    func testMissingContextFallsBackToMaxTokensThen200k() throws {
        let c = try ModelCatalogImporter.normalise(litellm: fixture(), generatedAt: Date())
        XCTAssertEqual(c.entries["claude-test-max-tokens-only"]?.contextWindow, 131_072)
        XCTAssertEqual(c.entries["claude-test-no-context"]?.contextWindow, 200_000)
    }

    func testEntriesWithoutInputPriceAreDropped() throws {
        XCTAssertNil(try ModelCatalogImporter.normalise(litellm: fixture(), generatedAt: Date()).entries["claude-test-no-price"])
    }
    func testCanonicalPriceWinsOverConflictingCloudCopy() throws {
        var input = try fixture()
        var cloud = try XCTUnwrap(input["azure/gpt-5.6-sol"] as? [String: Any])
        cloud["input_cost_per_token"] = 0.99
        input["azure/gpt-5.6-sol"] = cloud
        let catalog = try ModelCatalogImporter.normalise(litellm: input, generatedAt: Date())
        XCTAssertEqual(catalog.entries["gpt-5.6-sol"]?.inputPerMTok, 4)
    }

    func testVertexGeminiImportsWithoutGeminiProviderAlias() throws {
        var input = try fixture()
        input.removeValue(forKey: "gemini/gemini-3.5-flash")
        let catalog = try ModelCatalogImporter.normalise(litellm: input, generatedAt: Date())
        XCTAssertEqual(catalog.entries["gemini-3.5-flash"]?.provider, "gemini")
    }

}
