# Model Catalog — auto-updating pricing, context windows and display names

- **Date**: 2026-09-05
- **Status**: approved
- **Scope**: sub-project A of "track every model without shipping a new build" (B = Gemini/Antigravity tracking, C = oMLX local agents — separate specs)

## Problem

Every new Claude/OpenAI/Gemini model currently requires a code change in `CostCalculator.pricing`, `SessionService.contextWindow(forModel:)` and a release. Between the model's release and that build, ClaudeBar silently mis-prices usage (Sonnet 5 was billed at Sonnet 4.6 rates for three months) and shows a wrong context gauge. The owner wants tracking of new models to switch on by itself.

## Decision

Pricing, context window and display metadata come from a **catalog** that ClaudeBar refreshes on its own from the public LiteLLM file `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json` (3 561 entries, verified 2026-09-05 to carry `claude-opus-5`, `claude-sonnet-5`, `claude-fable-5-1`, `gpt-6-astra`, `gpt-5.6-*`, `gemini-3.5-flash` at the prices ClaudeBar already hard-codes). A normalised snapshot of that catalog ships inside the app as the offline fallback. Unknown models are **estimated from their family** and flagged.

Alternatives considered: a `models.json` maintained in this repository by a weekly Claude routine (control, but depends on a routine and on human knowledge — kept as a possible override later); fetching the raw file on every computation (2 MB per calculation, network-bound — rejected).

## Components

### `ModelCatalog` (pure value, `Sendable`, `Sources/ClaudeBar/Models/ModelCatalog.swift`)

```swift
struct ModelCatalogEntry: Codable, Sendable, Equatable {
    let id: String                 // canonical id, e.g. "claude-opus-5"
    let provider: String           // "anthropic" | "openai" | "gemini" | other
    let family: String             // "opus" | "sonnet" | "haiku" | "fable" | "mythos" | "gpt" | "gemini" | …
    let inputPerMTok: Double
    let outputPerMTok: Double
    let cacheReadPerMTok: Double
    let cacheWritePerMTok: Double
    let contextWindow: Int         // max input tokens
}

struct ModelCatalog: Codable, Sendable {
    let generatedAt: Date
    let entries: [String: ModelCatalogEntry]
    struct Resolution { let entry: ModelCatalogEntry; let isEstimated: Bool; let basedOn: String? }
    func resolve(_ modelId: String) -> Resolution?
}
```

`resolve` is a three-stage cascade:
1. **Exact id**.
2. **Normalised alias**: lower-cased; date suffix `-YYYYMMDD` dropped; provider/cloud prefixes dropped (`anthropic/`, `anthropic.`, `us.anthropic.`, `eu.`, `global.`, `openai/`, `azure/`, `vertex_ai/`, `gemini/`, `bedrock/`, `bedrock_mantle/`); `@` version separators mapped to `-`.
3. **Family estimate**: same family (and same provider), newest generation known — "newest" = highest numeric version parsed from the id (`claude-opus-4-8` → 4.8, `claude-fable-5-1` → 5.1); ties broken by lexical order. Result carries `isEstimated = true` and `basedOn = <that id>`.
`nil` only when no family matches at all; callers then fall back to the Opus 5 entry from the bundled snapshot (never $0).

`displayName(for:)` and `modelColor(for:)` stay algorithmic (`StatsService.displayName`, `Color.modelColor`) — they already derive from the family and need no catalog data.

### `ModelCatalogService` (`@Observable @MainActor`, `Sources/ClaudeBar/Services/ModelCatalogService.swift`)

- Holds the current `ModelCatalog`, `source: .bundled | .cache | .remote`, `lastUpdated`, `lastError`, and `unknownModelsSeen: [String: String]` (id → basedOn).
- Load order at launch: disk cache (`~/Library/Application Support/ClaudeBar/model-catalog.json`) if it decodes, else the bundled snapshot (`Resources/model-catalog.json`, loaded through `Bundle.module`).
- Refresh at launch and every 24 h (single-flight, ETag/`If-None-Match`, 10 s timeout, injectable `URLSession`): download → `ModelCatalogImporter.normalise(litellmJSON:)` → keep only entries whose `litellm_provider` is `anthropic`, `openai`, `gemini` or `vertex_ai*`, plus any id containing `claude`, `gpt`, `codex`, `o1`–`o9`, `gemini`; drop cloud-prefixed duplicates once normalised to an existing id → atomic write of the cache → publish. Any failure keeps the current catalog and sets `lastError`.
- A static `ModelCatalogService.shared` gives the nonisolated cost/context helpers a synchronous read (the catalog value is copied into a lock-protected holder on every publish, so background scans read a consistent snapshot without touching the main actor).
- Records every estimated resolution it is asked for (`noteResolution`) and posts one `NotificationService` alert per new id: "New model detected: claude-xyz — priced like Opus 5 until the catalog knows it".

### Façades (no call-site changes)

- `CostCalculator.pricing(for:)` → `ModelCatalogService.shared.pricing(for:)`; the hard-coded table becomes the bundled snapshot generator's seed and is deleted from Swift. `ModelPricing` keeps its shape. `CostCalculator.isEstimated(modelId)` exposes the flag for the UI.
- `SessionService.contextWindow(forModel:)` → catalog `contextWindow`, fallback 200 000 when the resolution is `nil`.
- Fallback rules currently in `pricing(for:)` (partial matches, legacy Sonnet 3.x/4.x at $3/$15) are replaced by the cascade above; the bundled snapshot contains those legacy ids explicitly so the behaviour and the existing `CostCalculatorTests` are preserved.

### UI

- Dashboard cost line and Analytics › Models: a small "~" badge with tooltip "estimated — <id> priced like <basedOn>" whenever any model contributing to the figure is estimated.
- Settings › App: "Model catalog — <source>, updated <relative date>, N models" with a **Refresh now** button and the last error if any.

### Snapshot generation

- `scripts/generate_model_catalog.swift` (run via `make catalog`): downloads LiteLLM, applies the same `ModelCatalogImporter`, writes `Resources/model-catalog.json` (pretty-printed, sorted ids, `generatedAt`).
- `Package.swift`: `resources: [.copy("Resources/model-catalog.json")]` on `ClaudeBarLib` (resources are moved under `Sources/ClaudeBar/Resources/`; the app icon stays where it is).
- CI (`build.yml`): fails when the bundled snapshot's `generatedAt` is older than 90 days — a release cannot ship a stale fallback.

## Error handling

| Situation | Behaviour |
|---|---|
| No network / GitHub down | keep cache or bundled snapshot; `lastError` shown in Settings only |
| Cache file corrupt | ignore, use bundled snapshot, overwrite on next successful refresh |
| LiteLLM entry missing a cache price | derive: cache read = 10 % of input, cache write = 125 % of input |
| LiteLLM entry missing `max_input_tokens` | use `max_tokens` if present, else 200 000 |
| Model in JSONL absent from catalog | family estimate + flag + one notification |
| Family unknown (e.g. `<synthetic>`, `unknown`) | `<synthetic>` is skipped by scanners already; anything else resolves to Opus 5 pricing, flagged |

## Testing

- `ModelCatalogTests`: alias normalisation (≥ 20 real ids incl. `us.anthropic.claude-opus-5`, `claude-sonnet-4-5-20250929`, `claude-opus-4-5@20251101`, `azure/gpt-5.6-sol`), cascade order, family estimate picks the newest generation, `isEstimated` flag, legacy Sonnet pricing preserved.
- `ModelCatalogImporterTests`: normalises a trimmed LiteLLM fixture (checked into `Tests/Fixtures/litellm-sample.json`), derives missing cache prices, drops non-target providers.
- `ModelCatalogServiceTests`: bundled → cache → remote precedence, ETag/304, network failure keeps state, single-flight, unknown-model notification fires once (mock `URLSession` via the existing `URLProtocol` pattern, temp cache directory).
- Existing `CostCalculatorTests` and `SessionContextEstimateTests` pass unchanged (snapshot contains the same numbers).

## Out of scope

Per-agent attribution, Gemini/Antigravity parsing (B), oMLX (C), any pricing for local models (always $0, "API equivalent" is computed by C using this catalog).
