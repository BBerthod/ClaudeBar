import XCTest
@testable import ClaudeBarLib

final class ModelCatalogTests: XCTestCase {
    private func entry(_ id: String, provider: String = "anthropic", family: String = "opus",
                       input: Double = 5, output: Double = 25, read: Double = 0.5, write: Double = 6.25,
                       context: Int = 1_000_000) -> ModelCatalogEntry {
        ModelCatalogEntry(id: id, provider: provider, family: family, inputPerMTok: input, outputPerMTok: output,
                          cacheReadPerMTok: read, cacheWritePerMTok: write, contextWindow: context)
    }

    private var catalog: ModelCatalog {
        ModelCatalog(generatedAt: Date(timeIntervalSince1970: 0), entries: [
            "claude-opus-5":      entry("claude-opus-5"),
            "claude-opus-4-8":    entry("claude-opus-4-8"),
            "claude-sonnet-5":    entry("claude-sonnet-5", family: "sonnet", input: 2, output: 10, read: 0.2, write: 2.5),
            "claude-sonnet-4-6":  entry("claude-sonnet-4-6", family: "sonnet", input: 3, output: 15, read: 0.3, write: 3.75),
            "claude-haiku-4-5":   entry("claude-haiku-4-5", family: "haiku", input: 1, output: 5, read: 0.1, write: 1.25, context: 200_000),
            "claude-fable-5-1":   entry("claude-fable-5-1", family: "fable", input: 10, output: 50, read: 0.25, write: 12.5),
            "gpt-5.6-sol":        entry("gpt-5.6-sol", provider: "openai", family: "gpt", input: 4, output: 20, read: 0.4, write: 5, context: 922_000),
        ])
    }

    func testNormalizerStripsDateSuffixAndCloudPrefixes() {
        XCTAssertEqual(ModelIdNormalizer.normalize("claude-sonnet-4-5-20250929"), "claude-sonnet-4-5")
        XCTAssertEqual(ModelIdNormalizer.normalize("us.anthropic.claude-opus-5"), "claude-opus-5")
        XCTAssertEqual(ModelIdNormalizer.normalize("anthropic/claude-opus-5"), "claude-opus-5")
        XCTAssertEqual(ModelIdNormalizer.normalize("global.anthropic.claude-fable-5-1"), "claude-fable-5-1")
        XCTAssertEqual(ModelIdNormalizer.normalize("azure/eu/gpt-5.6-sol"), "gpt-5.6-sol")
        XCTAssertEqual(ModelIdNormalizer.normalize("bedrock_mantle/openai.gpt-5.6-sol"), "gpt-5.6-sol")
        XCTAssertEqual(ModelIdNormalizer.normalize("claude-opus-4-5@20251101"), "claude-opus-4-5")
        XCTAssertEqual(ModelIdNormalizer.normalize("Claude-Opus-5"), "claude-opus-5")
    }

    func testAdditionalAliases() {
        let aliases = [
            "anthropic.claude-opus-5", "eu.anthropic.claude-opus-5", "au.anthropic.claude-opus-5",
            "jp.anthropic.claude-opus-5", "bedrock/claude-opus-5", "vertex_ai/claude-opus-5",
            "global.claude-opus-5", "claude-opus-5-20260101", "claude-opus-5@20260101",
            "bedrock/us.anthropic.claude-opus-5", "azure/claude-opus-5", "us.claude-opus-5"
        ]
        for alias in aliases { XCTAssertEqual(ModelIdNormalizer.normalize(alias), "claude-opus-5", alias) }
        XCTAssertEqual(ModelIdNormalizer.normalize("openai/gpt-6-astra"), "gpt-6-astra")
        XCTAssertEqual(ModelIdNormalizer.normalize("gemini/gemini-3.5-flash"), "gemini-3.5-flash")
    }

    func testFamilyEstimateUsesProviderAndLexicalTieBreak() throws {
        let c = ModelCatalog(generatedAt: Date(), entries: [
            "gpt-6-astra": entry("gpt-6-astra", provider: "openai", family: "gpt"),
            "gpt-6-sol": entry("gpt-6-sol", provider: "openai", family: "gpt"),
            "gpt-99": entry("gpt-99", provider: "other", family: "gpt")
        ])
        XCTAssertEqual(try XCTUnwrap(c.resolve("gpt-7")).basedOn, "gpt-6-sol")
    }

    func testFamilyAndVersionDetection() throws {
        XCTAssertEqual(ModelIdNormalizer.family(of: "claude-opus-5"), "opus")
        XCTAssertEqual(ModelIdNormalizer.family(of: "claude-3-7-sonnet"), "sonnet")
        XCTAssertEqual(ModelIdNormalizer.family(of: "claude-mythos-5-1"), "mythos")
        XCTAssertEqual(ModelIdNormalizer.family(of: "gpt-6-astra"), "gpt")
        XCTAssertEqual(ModelIdNormalizer.family(of: "gemini-3.5-flash"), "gemini")
        XCTAssertNil(ModelIdNormalizer.family(of: "<synthetic>"))
        XCTAssertEqual(try XCTUnwrap(ModelIdNormalizer.version(of: "claude-opus-4-8")), 4.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ModelIdNormalizer.version(of: "claude-fable-5-1")), 5.1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ModelIdNormalizer.version(of: "claude-3-7-sonnet-20250219")), 3.7, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ModelIdNormalizer.version(of: "gpt-5.6-sol")), 5.6, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ModelIdNormalizer.version(of: "claude-opus-5")), 5.0, accuracy: 0.001)
    }

    func testResolveExactThenAliasThenFamily() throws {
        let exact = try XCTUnwrap(catalog.resolve("claude-sonnet-5"))
        XCTAssertFalse(exact.isEstimated); XCTAssertEqual(exact.entry.inputPerMTok, 2)

        let alias = try XCTUnwrap(catalog.resolve("us.anthropic.claude-sonnet-4-6-20260101"))
        XCTAssertFalse(alias.isEstimated); XCTAssertEqual(alias.entry.id, "claude-sonnet-4-6")

        let estimated = try XCTUnwrap(catalog.resolve("claude-opus-6"))
        XCTAssertTrue(estimated.isEstimated)
        XCTAssertEqual(estimated.basedOn, "claude-opus-5")          // newest opus generation
        XCTAssertEqual(estimated.entry.inputPerMTok, 5)

        let sonnetFuture = try XCTUnwrap(catalog.resolve("claude-sonnet-7"))
        XCTAssertEqual(sonnetFuture.basedOn, "claude-sonnet-5")     // 5 > 4.6

        let gpt = try XCTUnwrap(catalog.resolve("gpt-7-nova"))
        XCTAssertEqual(gpt.basedOn, "gpt-5.6-sol")
        XCTAssertNil(catalog.resolve("<synthetic>"))
        XCTAssertNil(catalog.resolve("llama-4-70b"))                 // unknown family
    }

    func testDatedIdsDoNotBecomeHugeVersions() throws {
        XCTAssertEqual(ModelIdNormalizer.normalize("gpt-5-2025-08-07"), "gpt-5")
        XCTAssertEqual(try XCTUnwrap(ModelIdNormalizer.version(of: "gpt-5-2025-08-07")), 5.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ModelIdNormalizer.version(of: "gpt-4.1-2025-04-14")), 4.1, accuracy: 0.001)
        var entries = catalog.entries
        entries["gpt-6-astra"] = entry("gpt-6-astra", provider: "openai", family: "gpt", input: 10, output: 50, read: 1, write: 12.5, context: 922_000)
        entries["gpt-5-2025-08-07"] = entry("gpt-5-2025-08-07", provider: "openai", family: "gpt", input: 1.25, output: 10, read: 0.125, write: 1.5, context: 272_000)
        let c = ModelCatalog(generatedAt: Date(), entries: entries)
        XCTAssertEqual(c.resolve("gpt-7-nova")?.basedOn, "gpt-6-astra")
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(ModelCatalog.self, from: data)
        XCTAssertEqual(decoded.entries.count, 7)
        XCTAssertEqual(decoded.entries["claude-fable-5-1"]?.cacheReadPerMTok, 0.25)
    }
}
