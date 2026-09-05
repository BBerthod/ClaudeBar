# oMLX — local agents tracking

- **Date**: 2026-09-05
- **Status**: approved (owner: "tu peux y aller")
- **Scope**: sub-project C. Depends on A (model catalog) for the "API equivalent" figure.

## Problem

`OmlxMonitorService` only polls `GET /health` (status, default model, engine-pool memory). The owner runs local agents against oMLX (`jundot/omlx`, 0.6.x) and wants to see what they consume — per model, per day — the way Claude/Codex usage is shown.

## Facts (verified 2026-09-05 on the owner's machine)

- `~/.omlx/stats.json` — persisted, cumulative since install: `total_prompt_tokens`, `total_completion_tokens`, `total_cached_tokens`, `total_requests`, `total_prefill_duration`, `total_generation_duration`, and `per_model: { "<model>": { prompt_tokens, completion_tokens, cached_tokens, requests, prefill_duration, generation_duration } }`. Rewritten by the server as requests complete.
- `~/.omlx/settings.json` — `port` (8000) and `api_key` (`omlx-…`). Never display or log the key.
- `GET /health` — no auth. `GET /v1/models/status` — Bearer/`x-api-key` auth; per model: loaded, loading, last access, estimated size (field names to confirm at implementation time against the live server; parse tolerantly).
- No per-agent attribution exists server-side; only API sub-keys could provide it (future work).

## Decision

1. **Daily deltas from `stats.json`.** `OmlxUsageService` (new, `@Observable @MainActor`) watches `~/.omlx/stats.json` (existing `FileWatcher`) and keeps a **daily baseline** at `~/Library/Application Support/ClaudeBar/omlx-baseline.json` = `{ "date": "YYYY-MM-DD", "snapshot": <stats.json contents at first sight that day> }`. Today's usage per model = current − baseline (clamped at 0; if a counter went *down*, oMLX was reset → new baseline = current). Exposes `todayPerModel: [OmlxModelUsage]` (model, promptTokens, completionTokens, cachedTokens, requests, generationTokensPerSecond = completion / generationDuration), `todayTotals`, `allTimeTotals`.
2. **Loaded models** via `/v1/models/status` every 30 s using the key from `settings.json` (read at each poll, so a rotated key is picked up). Exposes `loadedModels: [OmlxLoadedModel]` (id, isLoaded, isLoading, lastAccess?, sizeGB?). 401/404 → `loadedModels = []`, `lastError` set, no retry storm (existing 30 s cadence).
3. **API-equivalent cost**: for each model, `CostCalculator.pricing(for:)` of a *reference* model chosen by the user in Settings (`claudebar.omlxReferenceModel`, default `claude-sonnet-5`) × today's tokens → "≈ $X if this had been Sonnet 5". Local cost itself is always $0.
4. **UI**: Dashboard provider card "oMLX" shows requests today, tokens today, active/loaded model, "≈ $X saved"; Analytics › System oMLX block gains a per-model table (tokens, requests, tok/s, last access) and the reference-model picker. Existing `/health` panel unchanged.
5. `ProviderUsageService.omlxCallsToday` (currently derived elsewhere) is replaced by the new service's `todayTotals.requests`; remove the old derivation.

Alternatives: parsing `~/.omlx/logs/server.log` (unstructured, rotates — rejected); a local proxy in front of oMLX to attribute per client (heavy, changes the owner's setup — rejected for now).

## Error handling

| Situation | Behaviour |
|---|---|
| `stats.json` missing / unparsable | service inactive (`isAvailable = false`), card hidden as today |
| baseline missing (first run of the day) | baseline = current, today = 0 |
| counters decrease | reset detected → new baseline, log info |
| `settings.json` unreadable | health-only mode, `loadedModels = []`, no error shown (key is optional) |
| server down | `/health` failure already handled; stats deltas still shown (file-based) |

## Testing

- `OmlxUsageServiceTests`: delta computation from two fixture snapshots (incl. new model appearing mid-day, counter reset, baseline rollover at midnight via injected `now`), baseline persistence round-trip in a temp dir, tok/s division by zero → 0.
- `OmlxModelsStatusTests`: tolerant decoding of `/v1/models/status` with missing fields; 401 → empty + `lastError`.
- API-equivalent cost: pure function `apiEquivalentCost(usage:referencePricing:)` tested with hand-computed values.

## Out of scope

Per-agent attribution, sub-key management, non-oMLX local servers (Ollama, LM Studio).
