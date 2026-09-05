# Model Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pricing, context windows and "estimated" flags for every model come from a catalog ClaudeBar refreshes itself from LiteLLM, with a bundled snapshot as fallback, so new models are tracked without a new build.

**Architecture:** A pure `ModelCatalog` value (id → entry, three-stage resolution: exact → normalised alias → family estimate) is produced by `ModelCatalogImporter` from the LiteLLM JSON, cached on disk by `ModelCatalogService` (24 h refresh, ETag, single-flight) and read synchronously by the existing `CostCalculator` / `SessionService.contextWindow` façades through a lock-protected holder. The bundled fallback is a generated Swift source file (no SPM resources → nothing to bundle in `make app`, works in tests).

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, SPM, XCTest (+ existing `URLProtocol` mocks), macOS 14+. Zero runtime dependencies. CI fails on any Swift warning.

**Spec:** `docs/superpowers/specs/2026-09-05-model-catalog-design.md` (one deviation, decided here: the bundled snapshot is a generated Swift file `Sources/ClaudeBar/Models/ModelCatalogSnapshot.swift`, not an SPM resource — `Bundle.module` would require copying the resource bundle into the `.app` in the Makefile and behaves differently under `swift test`).

**Verification commands (every task):**
```bash
swift build 2>&1 | grep -E "warning:.*\.swift|error:"      # must print NOTHING
swift test 2>&1 | grep -E "Executed [0-9]+ tests|Test run with" | tail -2   # 0 failures
```
(If SwiftPM caches are blocked by a sandbox: `swift build --disable-sandbox` with `--cache-path /tmp/...`.)

---

## File structure

| File | Responsibility |
|---|---|
| `Sources/ClaudeBar/Models/ModelCatalog.swift` | `ModelCatalogEntry`, `ModelCatalog`, `ModelIdNormalizer`, `resolve` cascade — pure, `Sendable`, no I/O |
| `Sources/ClaudeBar/Models/ModelCatalogImporter.swift` | LiteLLM JSON (`[String: Any]`) → `ModelCatalog`; provider filter, price derivation |
| `Sources/ClaudeBar/Models/ModelCatalogSnapshot.swift` | **generated** — `enum ModelCatalogSnapshot { static let json: String; static let generatedAt: String }` |
| `scripts/generate_model_catalog.swift` | downloads LiteLLM, runs the importer logic (duplicated minimal copy — script can't import the lib), writes the snapshot file |
| `Makefile` | `catalog` target |
| `.github/workflows/build.yml` | snapshot freshness gate (≤ 90 days) |
| `Sources/ClaudeBar/Services/ModelCatalogService.swift` | `@Observable @MainActor` service: load (cache → snapshot), refresh (remote, ETag, single-flight), `shared` nonisolated holder, unknown-model bookkeeping |
| `Sources/ClaudeBar/Utilities/CostCalculator.swift` | façade over the catalog; hard-coded table removed |
| `Sources/ClaudeBar/Services/SessionService.swift` | `contextWindow(forModel:)` façade |
| `Sources/ClaudeBar/Services/NotificationService.swift` | `sendNewModelDetected(id:basedOn:)` |
| `Sources/ClaudeBar/Views/Settings/SettingsAppSection.swift` | catalog status row + Refresh button |
| `Sources/ClaudeBar/Views/DashboardView.swift`, `Sources/ClaudeBar/Views/ModelsBreakdownView.swift` | "~" estimated badge |
| `Tests/ClaudeBarTests/ModelCatalogTests.swift`, `ModelCatalogImporterTests.swift`, `ModelCatalogServiceTests.swift`, `ModelCatalogSnapshotTests.swift` | tests |
| `Tests/ClaudeBarTests/Fixtures/litellm-sample.json` | trimmed LiteLLM fixture (≈ 25 entries) — loaded via `Bundle.module` **in the test target only** (`resources: [.copy("Fixtures")]` on the test target in `Package.swift`) |

---

### Task 1: `ModelCatalog` value type and id normalisation

**Files:**
- Create: `Sources/ClaudeBar/Models/ModelCatalog.swift`
- Test: `Tests/ClaudeBarTests/ModelCatalogTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
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

    func testFamilyAndVersionDetection() {
        XCTAssertEqual(ModelIdNormalizer.family(of: "claude-opus-5"), "opus")
        XCTAssertEqual(ModelIdNormalizer.family(of: "claude-3-7-sonnet"), "sonnet")
        XCTAssertEqual(ModelIdNormalizer.family(of: "claude-mythos-5-1"), "mythos")
        XCTAssertEqual(ModelIdNormalizer.family(of: "gpt-6-astra"), "gpt")
        XCTAssertEqual(ModelIdNormalizer.family(of: "gemini-3.5-flash"), "gemini")
        XCTAssertNil(ModelIdNormalizer.family(of: "<synthetic>"))
        XCTAssertEqual(ModelIdNormalizer.version(of: "claude-opus-4-8"), 4.8, accuracy: 0.001)
        XCTAssertEqual(ModelIdNormalizer.version(of: "claude-fable-5-1"), 5.1, accuracy: 0.001)
        XCTAssertEqual(ModelIdNormalizer.version(of: "claude-3-7-sonnet-20250219"), 3.7, accuracy: 0.001)
        XCTAssertEqual(ModelIdNormalizer.version(of: "gpt-5.6-sol"), 5.6, accuracy: 0.001)
        XCTAssertEqual(ModelIdNormalizer.version(of: "claude-opus-5"), 5.0, accuracy: 0.001)
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

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(ModelCatalog.self, from: data)
        XCTAssertEqual(decoded.entries.count, 7)
        XCTAssertEqual(decoded.entries["claude-fable-5-1"]?.cacheReadPerMTok, 0.25)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter ModelCatalogTests` → compile error (types undefined).

- [ ] **Step 3: Implement**

```swift
import Foundation

struct ModelCatalogEntry: Codable, Sendable, Equatable {
    let id: String
    let provider: String
    let family: String
    let inputPerMTok: Double
    let outputPerMTok: Double
    let cacheReadPerMTok: Double
    let cacheWritePerMTok: Double
    let contextWindow: Int
}

/// Canonicalises vendor/cloud-prefixed and date-suffixed model ids.
enum ModelIdNormalizer {
    private static let prefixes = ["anthropic/", "anthropic.", "openai/", "openai.", "azure/", "vertex_ai/",
                                   "gemini/", "bedrock/", "bedrock_mantle/", "global.", "us.", "eu.", "au.", "jp."]
    static let families = ["fable", "mythos", "opus", "sonnet", "haiku", "gpt", "codex", "gemini"]

    static func normalize(_ raw: String) -> String {
        var id = raw.lowercased()
        var changed = true
        while changed {                       // "azure/eu/gpt-…", "bedrock_mantle/openai.gpt-…"
            changed = false
            for p in prefixes where id.hasPrefix(p) { id.removeFirst(p.count); changed = true }
            if let slash = id.firstIndex(of: "/") { id = String(id[id.index(after: slash)...]); changed = true }
        }
        if let at = id.firstIndex(of: "@") { id = String(id[..<at]) }                 // claude-opus-4-5@20251101
        if let r = id.range(of: #"-\d{8}$"#, options: .regularExpression) { id = String(id[..<r.lowerBound]) }
        return id
    }

    static func family(of raw: String) -> String? {
        let id = normalize(raw)
        return families.first { id.contains($0) }   // "fable" before "opus": order matters for "claude-fable-…"
    }

    /// First numeric run after the family name, "4-8" / "4.8" / "5" → 4.8 / 4.8 / 5.0. Segments after the minor are ignored.
    static func version(of raw: String) -> Double? {
        let id = normalize(raw)
        let parts = id.split(whereSeparator: { $0 == "-" || $0 == "." || $0 == "_" }).map(String.init)
        guard let familyIdx = parts.firstIndex(where: { families.contains($0) }) else { return nil }
        // Version digits may sit before ("claude-3-7-sonnet") or after ("claude-opus-4-8") the family token.
        let after = parts[(familyIdx + 1)...].prefix { $0.allSatisfy(\.isNumber) }
        let before = parts[..<familyIdx].reversed().prefix { $0.allSatisfy(\.isNumber) }.reversed()
        let digits = after.isEmpty ? Array(before) : Array(after)
        guard let major = digits.first.flatMap(Double.init) else { return nil }
        let minor = digits.dropFirst().first.flatMap(Double.init) ?? 0
        return major + minor / 10
    }
}

struct ModelCatalog: Codable, Sendable {
    let generatedAt: Date
    let entries: [String: ModelCatalogEntry]

    struct Resolution: Sendable {
        let entry: ModelCatalogEntry
        let isEstimated: Bool
        let basedOn: String?
    }

    func resolve(_ modelId: String) -> Resolution? {
        if let e = entries[modelId] { return Resolution(entry: e, isEstimated: false, basedOn: nil) }
        let normalized = ModelIdNormalizer.normalize(modelId)
        if let e = entries[normalized] { return Resolution(entry: e, isEstimated: false, basedOn: nil) }
        guard let family = ModelIdNormalizer.family(of: normalized) else { return nil }
        let provider = entries.values.first { $0.family == family }?.provider
        let candidates = entries.values.filter { $0.family == family && $0.provider == provider }
        guard let best = candidates.max(by: { a, b in
            let va = ModelIdNormalizer.version(of: a.id) ?? 0, vb = ModelIdNormalizer.version(of: b.id) ?? 0
            return va == vb ? a.id < b.id : va < vb
        }) else { return nil }
        return Resolution(entry: best, isEstimated: true, basedOn: best.id)
    }
}
```

- [ ] **Step 4: Run tests** — `swift test --filter ModelCatalogTests` → all pass. Fix `version(of:)` edge cases against the assertions above before moving on.

- [ ] **Step 5: Commit** — `git add Sources/ClaudeBar/Models/ModelCatalog.swift Tests/ClaudeBarTests/ModelCatalogTests.swift && git commit -m "feat(catalog): add ModelCatalog value type with alias and family resolution."`

---

### Task 2: LiteLLM importer

**Files:**
- Create: `Sources/ClaudeBar/Models/ModelCatalogImporter.swift`
- Create: `Tests/ClaudeBarTests/Fixtures/litellm-sample.json` — ~25 real entries copied verbatim from the LiteLLM file: `claude-opus-5`, `claude-sonnet-5`, `claude-sonnet-4-6`, `claude-haiku-4-5`, `claude-fable-5`, `claude-fable-5-1`, `us.anthropic.claude-opus-5`, `anthropic.claude-fable-5-1`, `claude-3-7-sonnet-20250219`, `gpt-6-astra`, `gpt-5.6-sol`, `azure/gpt-5.6-sol`, `gemini-3.5-flash`, `gemini/gemini-3.5-flash`, plus one entry per rejected provider (`ollama/...`, `mistral/...`, `groq/...`), one entry without `cache_read_input_token_cost`, one without `max_input_tokens` but with `max_tokens`, one `sample_spec` entry (LiteLLM's schema example — must be dropped).
- Modify: `Package.swift` — test target gets `resources: [.copy("Fixtures")]`.
- Test: `Tests/ClaudeBarTests/ModelCatalogImporterTests.swift`

- [ ] **Step 1: Failing tests**

```swift
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
}
```
(Add the four `claude-test-*` synthetic entries to the fixture with `litellm_provider: "anthropic"`.)

- [ ] **Step 2: Run — fails (type undefined / fixture missing).**

- [ ] **Step 3: Implement**

```swift
import Foundation

enum ModelCatalogImporter {
    static let targetProviders: Set<String> = ["anthropic", "openai", "gemini"]
    static let targetIdMarkers = ["claude", "gpt", "codex", "gemini"]

    static func normalise(litellm: [String: Any], generatedAt: Date) throws -> ModelCatalog {
        var entries: [String: ModelCatalogEntry] = [:]
        for (rawId, value) in litellm {
            guard rawId != "sample_spec", let dict = value as? [String: Any] else { continue }
            let provider = (dict["litellm_provider"] as? String ?? "").lowercased()
            let isTarget = targetProviders.contains(provider) || provider.hasPrefix("vertex_ai")
                || targetIdMarkers.contains { rawId.lowercased().contains($0) }
            guard isTarget else { continue }
            guard let input = dict["input_cost_per_token"] as? Double,
                  let output = dict["output_cost_per_token"] as? Double else { continue }
            let id = ModelIdNormalizer.normalize(rawId)
            guard let family = ModelIdNormalizer.family(of: id) else { continue }
            if let existing = entries[id], existing.id == rawId.lowercased() { continue }  // canonical wins over prefixed copy
            let read = (dict["cache_read_input_token_cost"] as? Double) ?? input * 0.10
            let write = (dict["cache_creation_input_token_cost"] as? Double) ?? input * 1.25
            let context = (dict["max_input_tokens"] as? Int) ?? (dict["max_tokens"] as? Int) ?? 200_000
            let canonicalProvider: String = family == "gpt" || family == "codex" ? "openai"
                : family == "gemini" ? "gemini" : "anthropic"
            entries[id] = ModelCatalogEntry(id: id, provider: canonicalProvider, family: family,
                                            inputPerMTok: input * 1_000_000, outputPerMTok: output * 1_000_000,
                                            cacheReadPerMTok: read * 1_000_000, cacheWritePerMTok: write * 1_000_000,
                                            contextWindow: context)
        }
        return ModelCatalog(generatedAt: generatedAt, entries: entries)
    }
}
```
Duplicate handling: iterate in sorted key order so the un-prefixed id (shorter, sorts first among equals after normalisation) is written first and prefixed copies are skipped when `entries[id]` already exists — replace the `existing` line by `if entries[id] != nil { continue }` and iterate `litellm.keys.sorted { $0.count < $1.count || ($0.count == $1.count && $0 < $1) }`.

- [ ] **Step 4: Tests pass.** — [ ] **Step 5: Commit** `feat(catalog): import LiteLLM pricing into ModelCatalog.`

---

### Task 3: Bundled snapshot generator + freshness gate

**Files:**
- Create: `scripts/generate_model_catalog.swift` (standalone `swift` script: `curl`-free — uses `URLSession` synchronously via `DispatchSemaphore`; contains a **copy** of `ModelIdNormalizer` + importer logic in a `// MIRROR OF Sources/ClaudeBar/Models — keep in sync` block), writes `Sources/ClaudeBar/Models/ModelCatalogSnapshot.swift`:

```swift
// Generated by `make catalog` on 2026-09-05T18:00:00Z — do not edit by hand.
enum ModelCatalogSnapshot {
    static let generatedAt = "2026-09-05T18:00:00Z"
    static let json = #"""
    {"generatedAt":..., "entries":{...}}   // ModelCatalog encoded with ISO8601 dates, sorted keys
    """#
}
```
- Modify: `Makefile` — `catalog:` target → `swift scripts/generate_model_catalog.swift`.
- Modify: `.github/workflows/build.yml` — step "Model catalog freshness": parse `generatedAt` from the snapshot with `grep -o`, fail if older than 90 days (`date -j -f` on macOS).
- Test: `Tests/ClaudeBarTests/ModelCatalogSnapshotTests.swift`

```swift
func testBundledSnapshotDecodesAndKnowsCurrentModels() throws {
    let catalog = try ModelCatalog.bundled()
    for id in ["claude-opus-5", "claude-sonnet-5", "claude-fable-5-1", "claude-opus-4-8", "claude-haiku-4-5",
               "claude-sonnet-4-6", "claude-3-7-sonnet", "gpt-6-astra", "gpt-5.6-sol", "gemini-3.5-flash"] {
        XCTAssertNotNil(catalog.entries[id], id)
    }
    XCTAssertEqual(catalog.entries["claude-sonnet-5"]?.inputPerMTok, 2)
    XCTAssertGreaterThan(catalog.entries.count, 50)
}
```
`ModelCatalog.bundled()` (add to `ModelCatalog.swift`): decode `ModelCatalogSnapshot.json` with `JSONDecoder` + `.iso8601` date strategy; `static let bundledCache = try! bundled()` is **not** allowed — keep it throwing, cache in the service.

- [ ] Run `make catalog` once to produce the real snapshot; commit generator + snapshot + test: `feat(catalog): bundle a generated LiteLLM snapshot and gate its freshness in CI.`

---

### Task 4: `ModelCatalogService`

**Files:**
- Create: `Sources/ClaudeBar/Services/ModelCatalogService.swift`
- Test: `Tests/ClaudeBarTests/ModelCatalogServiceTests.swift` (mock `URLProtocol` as in `UpdateCheckServiceNetworkTests.swift`; temp cache dir per test)

API (exact):
```swift
@Observable @MainActor
final class ModelCatalogService {
    enum Source: String, Sendable { case bundled, cache, remote }
    private(set) var catalog: ModelCatalog
    private(set) var source: Source
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?
    private(set) var unknownModelsSeen: [String: String] = [:]      // id → basedOn
    var onNewModelDetected: ((String, String) -> Void)?              // wired to NotificationService by AppDelegate

    static let remoteURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    static let refreshInterval: TimeInterval = 24 * 3600

    init(cacheDirectory: URL = <Application Support>/ClaudeBar, session: URLSession = .shared, disablePolling: Bool = false)
    func refresh() async                       // single-flight; ETag; keeps state on failure
    func noteResolution(_ r: ModelCatalog.Resolution, for id: String)   // records + fires onNewModelDetected once per id

    /// Nonisolated read for background scanners and CostCalculator.
    nonisolated static var current: ModelCatalog { Holder.shared.catalog }   // lock-protected; seeded with the bundled snapshot
}
```
Behaviour to test:
1. `testStartsFromBundledWhenNoCache` → `source == .bundled`, `catalog.entries["claude-opus-5"] != nil`.
2. `testLoadsCacheWhenPresent` → write a catalog JSON (with a marker entry `claude-cache-marker`) to the temp cache; `source == .cache`, marker present.
3. `testCorruptCacheFallsBackToBundled` → write `"not json"`; `.bundled`, `lastError == nil` (corrupt cache is not an error the user needs).
4. `testRefreshWritesCacheAndPublishes` → mock 200 with the fixture JSON + `ETag: "abc"`; after `refresh()`: `source == .remote`, cache file exists and decodes, `ModelCatalogService.current.entries["claude-opus-5"] != nil`, second `refresh()` sends `If-None-Match: "abc"`, mock replies 304 → state unchanged, `lastError == nil`.
5. `testRefreshFailureKeepsCatalog` → mock 500 → `source` unchanged, `lastError == "HTTP 500"`.
6. `testConcurrentRefreshesShareOneRequest` → two `async let` refreshes, request counter == 1.
7. `testNoteResolutionFiresOncePerModel` → `onNewModelDetected` called once for two notes of the same id; not called for non-estimated resolutions.

Implementation notes: `Holder` is `final class Holder: @unchecked Sendable { static let shared; private let lock = NSLock(); var catalog: ModelCatalog }` seeded with `(try? ModelCatalog.bundled()) ?? ModelCatalog(generatedAt: .distantPast, entries: [:])`; the service writes `Holder.shared.catalog = catalog` on every publish. Cache write: `Data.write(to:options:.atomic)`. Timer via the existing `ServiceTimer` helper (`Utilities/ServiceTimer.swift`), invalidated in `deinit`, not started when `disablePolling`.

- [ ] Tests first, then implementation, then commit `feat(catalog): add ModelCatalogService with cache, remote refresh and ETag.`

---

### Task 5: Route `CostCalculator` and `SessionService.contextWindow` through the catalog

**Files:**
- Modify: `Sources/ClaudeBar/Utilities/CostCalculator.swift` — delete the `pricing` dictionary and the partial-match cascade; keep `ModelPricing` and every public function signature.
- Modify: `Sources/ClaudeBar/Services/SessionService.swift` `contextWindow(forModel:)`.
- Modify: `Tests/ClaudeBarTests/CostCalculatorTests.swift` — **only** `testPricingFallbackToOpus` may change semantics: an unknown *family* now resolves to the Opus 5 entry (assert `inputPerMTok == 5`), all other assertions stay as they are and must pass from the snapshot.

```swift
// CostCalculator
static func pricing(for modelId: String) -> ModelPricing {
    let catalog = ModelCatalogService.current
    let entry = catalog.resolve(modelId)?.entry ?? catalog.entries["claude-opus-5"] ?? ModelPricing.opus5Fallback
    return ModelPricing(inputPerMTok: entry.inputPerMTok, outputPerMTok: entry.outputPerMTok,
                        cacheReadPerMTok: entry.cacheReadPerMTok, cacheWritePerMTok: entry.cacheWritePerMTok)
}
static func isEstimated(_ modelId: String) -> Bool { ModelCatalogService.current.resolve(modelId)?.isEstimated ?? true }
```
(`ModelPricing.opus5Fallback` is a literal 5/25/0.5/6.25 for the impossible case of an empty catalog.)

```swift
// SessionService
nonisolated static func contextWindow(forModel model: String) -> Int {
    ModelCatalogService.current.resolve(model)?.entry.contextWindow ?? 200_000
}
```
`SessionContextEstimateTests.testContextWindowForModel` stays green (`claude-3-5-haiku` → haiku family → 200 000; `""` → nil → 200 000).

- [ ] Run the **full** suite; commit `refactor(cost): source pricing and context windows from the model catalog.`

---

### Task 6: Unknown-model detection and notification

**Files:**
- Modify: `Sources/ClaudeBar/Services/NotificationService.swift` — add
```swift
func sendNewModelDetected(id: String, basedOn: String) {
    sendNotification(title: "New model detected: \(StatsService.displayName(for: id))",
                     body: "\(id) is not in the pricing catalog yet — costs are estimated from \(basedOn).",
                     identifier: "claudebar.new-model.\(id)")
}
```
- Modify: `Sources/ClaudeBar/Services/LiveStatsService.swift`, `ProjectService.swift`, `YearlyHistoryService.swift` — scanners already collect model ids; after each scan, hand the distinct ids to `ModelCatalogService` on the main actor: `catalogService.noteModels(ids)` where `noteModels` resolves each id and calls `noteResolution`. Inject the service through the existing `AppDelegate` wiring (look at how `NotificationService` is passed around; add `ModelCatalogService` next to it — one instance created in `AppDelegate`, `onNewModelDetected` bound to `notificationService.sendNewModelDetected`).
- Test: `ModelCatalogServiceTests.testNoteModelsIgnoresKnownAndSynthetic` (`["claude-opus-5", "<synthetic>", "claude-opus-6"]` → one callback for `claude-opus-6`).

- [ ] Commit `feat(catalog): notify once when an unknown model appears in transcripts.`

---

### Task 7: UI — catalog status and "estimated" badge

**Files:**
- Modify: `Sources/ClaudeBar/Views/Settings/SettingsAppSection.swift` — under the version/update rows add a row "Model catalog": `"\(catalog.entries.count) models · \(source.rawValue) · updated \(relative lastUpdated or generatedAt)"`, a `Button("Refresh now") { Task { await catalogService.refresh() } }` (disabled while refreshing) and `lastError` in `.foregroundStyle(.orange)` when present. Pass `ModelCatalogService` the same way the section receives `statsService`.
- Modify: `Sources/ClaudeBar/Views/DashboardView.swift` (cost header) and `Sources/ClaudeBar/Views/ModelsBreakdownView.swift` (per-model rows): when `CostCalculator.isEstimated(modelId)` is true for any contributing model, append `Text("~").help("Estimated — \(id) is priced like \(basedOn)")`. Use the existing `effectiveTokensByModel` list on the Dashboard to know the contributing ids.
- Snapshot tests are untouched (these views have none).

- [ ] Build with zero warnings; commit `feat(catalog): show catalog status in Settings and flag estimated model costs.`

---

### Task 8: Docs, changelog, version

**Files:**
- Modify: `README.md` — "How It Works" table: new row `LiteLLM model catalog | Pricing and context windows for Claude, OpenAI and Gemini models, refreshed daily (bundled snapshot as fallback). Unknown models are estimated from their family and flagged "~".`; Privacy section: add `raw.githubusercontent.com` (catalog download, no data sent).
- Modify: `CONTRIBUTING.md` — "Run `make catalog` before a release to refresh the bundled snapshot; CI fails if it is older than 90 days."
- Modify: `CHANGELOG.md` — `## [1.2.0] — <date>` → Added: auto-updating model catalog…; Changed: hard-coded pricing table removed.
- Modify: `VERSION` → `1.2.0`.

- [ ] Commit `docs: document the model catalog.` then `chore(release): bump version to 1.2.0.`

---

## Self-review

- Spec coverage: components ✔ (Tasks 1–4), façades ✔ (5), detection/notification ✔ (6), UI ✔ (7), snapshot generation + CI gate ✔ (3), error table ✔ (2, 4), tests ✔. Deviation from spec (Swift file instead of SPM resource) recorded in the header.
- Types: `ModelCatalogEntry`, `ModelCatalog`, `ModelCatalog.Resolution`, `ModelIdNormalizer`, `ModelCatalogImporter.normalise(litellm:generatedAt:)`, `ModelCatalog.bundled()`, `ModelCatalogService.current`, `noteResolution`, `noteModels`, `isEstimated` — used consistently across tasks.
