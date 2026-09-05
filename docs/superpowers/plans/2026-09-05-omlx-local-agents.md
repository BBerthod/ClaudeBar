# oMLX Local Agents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show what local agents consume on oMLX today — per model tokens, requests, throughput, loaded models — plus the API-equivalent cost they avoided.

**Architecture:** `OmlxUsageService` derives *daily deltas* from oMLX's own cumulative `~/.omlx/stats.json` (file-watched) against a persisted daily baseline, and polls `/v1/models/status` with the API key read from `~/.omlx/settings.json`. Pure functions (`OmlxStats`, `OmlxDailyUsage.delta`, `apiEquivalentCost`) carry the logic; the service only does I/O and publishing. Existing `OmlxMonitorService` (`/health`) is untouched.

**Tech Stack:** Swift 5.9, SwiftUI, SPM, XCTest with temp directories and the existing `URLProtocol` mock pattern. Depends on the model catalog (`CostCalculator.pricing(for:)`).

**Spec:** `docs/superpowers/specs/2026-09-05-omlx-local-agents-design.md`

**Verification (every task):** `swift build 2>&1 | grep -E "warning:.*\.swift|error:"` prints nothing; `swift test 2>&1 | grep -E "Executed [0-9]+ tests|Test run with" | tail -2` shows 0 failures.

---

## File structure

| File | Responsibility |
|---|---|
| `Sources/ClaudeBar/Models/OmlxStats.swift` | `OmlxStats` (Codable mirror of `stats.json`: totals + `perModel`), `OmlxModelUsage`, `OmlxDailyUsage` with `static func delta(current:baseline:)` and `apiEquivalentCost(reference:)` |
| `Sources/ClaudeBar/Models/OmlxModelStatus.swift` | tolerant Codable for `/v1/models/status` items (`id`, `loaded`, `isLoading`, `lastAccess`, `estimatedSize`) |
| `Sources/ClaudeBar/Services/OmlxUsageService.swift` | `@Observable @MainActor`: watches `stats.json`, keeps `omlx-baseline.json`, polls models status every 30 s with the key from `settings.json`, exposes `todayPerModel`, `todayTotals`, `allTime`, `loadedModels`, `isAvailable`, `lastError`, `referenceModelId` (UserDefaults `claudebar.omlxReferenceModel`, default `claude-sonnet-5`) |
| `Sources/ClaudeBar/Views/Dashboard/DashboardProviderSummary.swift` | oMLX card: requests today, tokens today, active model, "≈ $X saved" |
| `Sources/ClaudeBar/Views/Analytics/AnalyticsSystemPanel.swift` | oMLX block: per-model table (tokens, requests, tok/s, last access), reference-model picker |
| `Sources/ClaudeBar/Services/ProviderUsageService.swift` | remove `omlxCallsToday`/`isOmlxActive` derivation; consumers read `OmlxUsageService` |
| `Sources/ClaudeBar/AppDelegate.swift` | instantiate + `.environment(omlxUsageService)` (popover and analytics window) |
| `Tests/ClaudeBarTests/OmlxStatsTests.swift`, `OmlxUsageServiceTests.swift` | tests |

---

### Task 1: `OmlxStats` model and daily delta

**Files:** create `Sources/ClaudeBar/Models/OmlxStats.swift`; test `Tests/ClaudeBarTests/OmlxStatsTests.swift`.

- [ ] Failing tests:

```swift
import XCTest
@testable import ClaudeBarLib

final class OmlxStatsTests: XCTestCase {
    private let sample = """
    {"total_prompt_tokens": 1000, "total_completion_tokens": 500, "total_cached_tokens": 100, "total_requests": 10,
     "total_prefill_duration": 2.0, "total_generation_duration": 50.0,
     "per_model": {
       "Qwen3.6-27B": {"prompt_tokens": 800, "completion_tokens": 400, "cached_tokens": 100, "requests": 8,
                       "prefill_duration": 1.5, "generation_duration": 40.0},
       "Qwen3-Next-80B": {"prompt_tokens": 200, "completion_tokens": 100, "cached_tokens": 0, "requests": 2,
                          "prefill_duration": 0.5, "generation_duration": 10.0}}}
    """

    func testDecodesStatsJSON() throws {
        let stats = try OmlxStats.decode(Data(sample.utf8))
        XCTAssertEqual(stats.totalRequests, 10)
        XCTAssertEqual(stats.perModel["Qwen3.6-27B"]?.completionTokens, 400)
        XCTAssertEqual(stats.perModel.count, 2)
    }

    func testDeltaSubtractsBaselinePerModel() throws {
        let baseline = try OmlxStats.decode(Data(sample.utf8))
        var current = baseline
        current.perModel["Qwen3.6-27B"] = OmlxModelUsage(promptTokens: 1300, completionTokens: 650, cachedTokens: 150,
                                                          requests: 13, prefillDuration: 2.0, generationDuration: 65.0)
        current.perModel["NewModel"] = OmlxModelUsage(promptTokens: 10, completionTokens: 20, cachedTokens: 0,
                                                       requests: 1, prefillDuration: 0.1, generationDuration: 2.0)
        let delta = OmlxDailyUsage.delta(current: current, baseline: baseline)
        XCTAssertFalse(delta.resetDetected)
        let qwen = try XCTUnwrap(delta.perModel.first { $0.model == "Qwen3.6-27B" })
        XCTAssertEqual(qwen.promptTokens, 500); XCTAssertEqual(qwen.completionTokens, 250); XCTAssertEqual(qwen.requests, 5)
        XCTAssertEqual(qwen.generationTokensPerSecond, 10, accuracy: 0.001)      // 250 / 25 s
        XCTAssertEqual(delta.perModel.first { $0.model == "NewModel" }?.completionTokens, 20) // model absent from baseline
        XCTAssertNil(delta.perModel.first { $0.model == "Qwen3-Next-80B" })      // unchanged → omitted
        XCTAssertEqual(delta.totals.requests, 6)
    }

    func testCounterDecreaseIsAReset() throws {
        let baseline = try OmlxStats.decode(Data(sample.utf8))
        var current = baseline
        current.perModel["Qwen3.6-27B"] = OmlxModelUsage(promptTokens: 5, completionTokens: 5, cachedTokens: 0,
                                                          requests: 1, prefillDuration: 0, generationDuration: 1)
        let delta = OmlxDailyUsage.delta(current: current, baseline: baseline)
        XCTAssertTrue(delta.resetDetected)
        XCTAssertEqual(delta.perModel.first { $0.model == "Qwen3.6-27B" }?.requests, 1)   // counted from zero
    }

    func testTokensPerSecondWithZeroDurationIsZero() {
        let u = OmlxModelUsage(promptTokens: 1, completionTokens: 50, cachedTokens: 0, requests: 1, prefillDuration: 0, generationDuration: 0)
        XCTAssertEqual(u.generationTokensPerSecond, 0)
    }

    func testApiEquivalentCostUsesReferencePricing() {
        let usage = OmlxModelUsage(promptTokens: 1_000_000, completionTokens: 100_000, cachedTokens: 0, requests: 1, prefillDuration: 1, generationDuration: 1)
        let pricing = CostCalculator.ModelPricing(inputPerMTok: 2, outputPerMTok: 10, cacheReadPerMTok: 0.2, cacheWritePerMTok: 2.5)
        XCTAssertEqual(OmlxDailyUsage.apiEquivalentCost(of: usage, reference: pricing), 3.0, accuracy: 1e-9) // 2 + 1
    }
}
```

- [ ] Implement:

```swift
import Foundation

struct OmlxModelUsage: Codable, Sendable, Equatable {
    var promptTokens: Int
    var completionTokens: Int
    var cachedTokens: Int
    var requests: Int
    var prefillDuration: Double
    var generationDuration: Double

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens", completionTokens = "completion_tokens", cachedTokens = "cached_tokens"
        case requests, prefillDuration = "prefill_duration", generationDuration = "generation_duration"
    }
    var generationTokensPerSecond: Double { generationDuration > 0 ? Double(completionTokens) / generationDuration : 0 }
}

struct OmlxStats: Codable, Sendable, Equatable {
    var totalPromptTokens: Int
    var totalCompletionTokens: Int
    var totalCachedTokens: Int
    var totalRequests: Int
    var totalPrefillDuration: Double
    var totalGenerationDuration: Double
    var perModel: [String: OmlxModelUsage]

    enum CodingKeys: String, CodingKey {
        case totalPromptTokens = "total_prompt_tokens", totalCompletionTokens = "total_completion_tokens"
        case totalCachedTokens = "total_cached_tokens", totalRequests = "total_requests"
        case totalPrefillDuration = "total_prefill_duration", totalGenerationDuration = "total_generation_duration"
        case perModel = "per_model"
    }
    static func decode(_ data: Data) throws -> OmlxStats { try JSONDecoder().decode(OmlxStats.self, from: data) }
}

struct OmlxDailyUsage: Sendable {
    struct ModelDelta: Sendable, Identifiable {
        let model: String; let usage: OmlxModelUsage
        var id: String { model }
        var promptTokens: Int { usage.promptTokens }; var completionTokens: Int { usage.completionTokens }
        var requests: Int { usage.requests }; var generationTokensPerSecond: Double { usage.generationTokensPerSecond }
    }
    let perModel: [ModelDelta]          // sorted by completion tokens desc, models with no change omitted
    let totals: OmlxModelUsage
    let resetDetected: Bool

    static func delta(current: OmlxStats, baseline: OmlxStats) -> OmlxDailyUsage {
        var reset = false
        var deltas: [ModelDelta] = []
        for (model, now) in current.perModel {
            let base = baseline.perModel[model]
            var d = now
            if let base {
                if now.requests < base.requests || now.completionTokens < base.completionTokens { reset = true }
                else {
                    d = OmlxModelUsage(promptTokens: now.promptTokens - base.promptTokens, completionTokens: now.completionTokens - base.completionTokens,
                                       cachedTokens: max(0, now.cachedTokens - base.cachedTokens), requests: now.requests - base.requests,
                                       prefillDuration: max(0, now.prefillDuration - base.prefillDuration),
                                       generationDuration: max(0, now.generationDuration - base.generationDuration))
                }
            }
            if d.requests > 0 || d.completionTokens > 0 || d.promptTokens > 0 { deltas.append(ModelDelta(model: model, usage: d)) }
        }
        deltas.sort { $0.completionTokens > $1.completionTokens }
        let totals = deltas.reduce(OmlxModelUsage(promptTokens: 0, completionTokens: 0, cachedTokens: 0, requests: 0, prefillDuration: 0, generationDuration: 0)) { acc, d in
            OmlxModelUsage(promptTokens: acc.promptTokens + d.usage.promptTokens, completionTokens: acc.completionTokens + d.usage.completionTokens,
                           cachedTokens: acc.cachedTokens + d.usage.cachedTokens, requests: acc.requests + d.usage.requests,
                           prefillDuration: acc.prefillDuration + d.usage.prefillDuration, generationDuration: acc.generationDuration + d.usage.generationDuration)
        }
        return OmlxDailyUsage(perModel: deltas, totals: totals, resetDetected: reset)
    }

    static func apiEquivalentCost(of usage: OmlxModelUsage, reference p: CostCalculator.ModelPricing) -> Double {
        Double(usage.promptTokens) / 1_000_000 * p.inputPerMTok + Double(usage.completionTokens) / 1_000_000 * p.outputPerMTok
    }
}
```
- [ ] Tests pass; commit `feat(omlx): add OmlxStats model with daily delta and API-equivalent cost.`

---

### Task 2: `/v1/models/status` decoding

**Files:** create `Sources/ClaudeBar/Models/OmlxModelStatus.swift`; tests in `Tests/ClaudeBarTests/OmlxStatsTests.swift` (add a second class `OmlxModelStatusTests`).

- [ ] Tests: decode `{"models":[{"id":"Qwen3.6-27B","loaded":true,"is_loading":false,"last_access":1757100000.5,"estimated_size":16000000000}]}` → one item, `isLoaded`, `sizeGB ≈ 16`; decode `[{"id":"x"}]` (bare array, missing fields) → `isLoaded == false`, `lastAccess == nil`; decode `{"data":[{"id":"y","status":"loaded"}]}` → loaded (accept `status == "loaded"` as well). Field names are not officially documented — the decoder must accept all three shapes.
- [ ] Implement `struct OmlxModelStatus: Sendable, Identifiable { let id: String; let isLoaded: Bool; let isLoading: Bool; let lastAccess: Date?; let sizeBytes: Int64? ; var sizeGB: Double? }` with `static func decodeList(_ data: Data) throws -> [OmlxModelStatus]` using `JSONSerialization` and tolerant key lookup (`models` / `data` / top-level array; `loaded` / `is_loaded` / `status == "loaded"`; `last_access` seconds or ms epoch; `estimated_size` / `size_bytes`).
- [ ] Commit `feat(omlx): decode /v1/models/status tolerantly.`

---

### Task 3: `OmlxUsageService`

**Files:** create `Sources/ClaudeBar/Services/OmlxUsageService.swift`; test `Tests/ClaudeBarTests/OmlxUsageServiceTests.swift`.

API:
```swift
@Observable @MainActor
final class OmlxUsageService {
    private(set) var isAvailable = false
    private(set) var today: OmlxDailyUsage?
    private(set) var allTime: OmlxStats?
    private(set) var loadedModels: [OmlxModelStatus] = []
    private(set) var lastError: String?
    var referenceModelId: String { get/set → UserDefaults "claudebar.omlxReferenceModel", default "claude-sonnet-5" }
    var todayApiEquivalentCost: Double   // sum over today.perModel with CostCalculator.pricing(for: referenceModelId)

    init(omlxDirectory: URL = ~/.omlx, baselineDirectory: URL = <App Support>/ClaudeBar, session: URLSession = .shared,
         now: @escaping () -> Date = Date.init, disablePolling: Bool = false)
    func reload()                 // re-reads stats.json + baseline; called by FileWatcher and at init
    func refreshModels() async    // /v1/models/status with key from settings.json; 30 s timer
}
```
Baseline file `omlx-baseline.json`: `{ "date": "YYYY-MM-DD" (local), "stats": OmlxStats }`. `reload()` rules: no `stats.json` → `isAvailable = false`; baseline missing or `date != today` → baseline := current, `today` = empty delta; delta reset → baseline := current, delta recomputed from zero (i.e. current values). Port and key: `settings.json` keys `port` (Int, default 8000) and `api_key` (String, optional); request `GET http://127.0.0.1:<port>/v1/models/status` with `Authorization: Bearer <key>` — never log the key.

- [ ] Tests (temp dirs, injected `now`): `testUnavailableWithoutStatsFile`; `testFirstSightCreatesBaselineAndZeroDelta`; `testDeltaAgainstPersistedBaseline` (write baseline for today with the sample, then stats with +5 requests → `today.totals.requests == 5`); `testBaselineRollsOverAtMidnight` (baseline dated yesterday → new baseline, delta zero); `testResetReplacesBaseline`; `testModelsStatusUsesKeyAndPort` (mock URLProtocol asserts `Authorization` header and port 8123 from settings) ; `testModelsStatus401ClearsListAndSetsError`; `testApiEquivalentCostUsesReferenceModel` (reference `claude-sonnet-5` → 2/10 pricing from the catalog).
- [ ] Implement with the existing `FileWatcher` (watch `stats.json`) and `ServiceTimer`; `deinit` invalidates.
- [ ] Commit `feat(omlx): track daily per-model usage from stats.json and loaded models.`

---

### Task 4: Wire into AppDelegate and replace the old oMLX counters

**Files:** `Sources/ClaudeBar/AppDelegate.swift` (instantiate `omlxUsageService`, add to both `.environment` chains), `Sources/ClaudeBar/Services/ProviderUsageService.swift` (delete `omlxCallsToday`, `isOmlxActive` and their derivation; update `Tests/ClaudeBarTests/ProviderUsageServiceOmlxTests.swift` accordingly — move any still-relevant assertions to `OmlxUsageServiceTests`), and every consumer found with `grep -rn "omlxCallsToday\|isOmlxActive" Sources` (Dashboard provider summary, Analytics system panel) → read `omlxUsageService.today?.totals.requests ?? 0` and `omlxUsageService.isAvailable`.

- [ ] Build with zero warnings, full suite green; commit `refactor(omlx): source oMLX activity from OmlxUsageService.`

---

### Task 5: UI

**Files:** `Sources/ClaudeBar/Views/Dashboard/DashboardProviderSummary.swift`, `Sources/ClaudeBar/Views/Analytics/AnalyticsSystemPanel.swift`.

- [ ] oMLX card (Dashboard): requests today, completion tokens today (formatted with the existing `Int.abbreviated`-style helper in `Utilities/Extensions.swift`), active model (`loadedModels.first { $0.isLoaded }?.id ?? allTime default model from `OmlxMonitorService`), and `"≈ \(CostCalculator.formatCost(todayApiEquivalentCost)) saved"` with `.help("API-equivalent cost if these tokens had gone to \(referenceModelId)")`. Hidden when `!isAvailable` (same behaviour as today).
- [ ] Analytics › System oMLX block: table rows per `today.perModel` — model, prompt/completion tokens, requests, `tok/s` (1 decimal), last access (relative, from `loadedModels`); a `Picker("Reference model", selection: referenceModelId)` listing `claude-sonnet-5`, `claude-opus-5`, `claude-haiku-4-5`, `claude-fable-5-1`; all-time totals line.
- [ ] Commit `feat(omlx): show local-agent usage, throughput and API-equivalent savings.`

---

### Task 6: Docs and version

- [ ] `README.md` Features › Dashboard: "**oMLX local usage** — tokens, requests and throughput per model for today, loaded models, and the API-equivalent cost you avoided"; How-It-Works table row for `~/.omlx/stats.json` + `/v1/models/status` (key read from `~/.omlx/settings.json`, never displayed); Privacy: `127.0.0.1:<port>/v1/models/status`.
- [ ] `CHANGELOG.md` `## [1.3.0] — <date>` Added; `VERSION` → `1.3.0`.
- [ ] Commit `docs: document oMLX local-agent tracking.` then `chore(release): bump version to 1.3.0.`

---

## Self-review

Spec coverage: deltas + baseline + reset ✔ (T1, T3), loaded models ✔ (T2, T3), API-equivalent with reference model ✔ (T1, T3, T5), UI ✔ (T5), old counters removed ✔ (T4), error table ✔ (T3 rules), tests ✔. Types consistent: `OmlxStats`, `OmlxModelUsage`, `OmlxDailyUsage(.delta, .apiEquivalentCost)`, `OmlxModelStatus(.decodeList)`, `OmlxUsageService(.reload, .refreshModels, .today, .loadedModels, .referenceModelId, .todayApiEquivalentCost)`.
