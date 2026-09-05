# Gemini / Antigravity — activity tracking

- **Date**: 2026-09-05
- **Status**: approved (owner: "tu peux y aller")
- **Scope**: sub-project B. Independent of A and C.

## Problem

`ProviderUsageService.refreshGemini()` reads `~/.gemini/oauth_creds.json`, which does not exist on the owner's machine (Gemini is used through Antigravity: IDE + `agy` CLI). The Gemini card is therefore always empty.

## Facts (verified 2026-09-05)

`~/.gemini/antigravity-cli/`:
- `conversation_summaries.db` — SQLite, table `conversation_summaries(conversation_id, title, preview, step_count, last_modified_time, workspace_uris, status, source, project_id, agent_name, parent_conversation_id, nesting_depth, not_fully_idle, killed, last_user_input_time, …)`.
- `history.jsonl` — one line per prompt: `{"display": "...", "timestamp": <ms>, "workspace": "/path", "conversationId": "..."}`.
- `antigravity-oauth-token` — presence/mtime only (contents never read).
- `conversations/*.db` — per-conversation SQLite whose payloads are protobuf blobs (model, tokens live there) — **not parsed**: opaque and version-dependent.
- `~/.gemini/antigravity/` (IDE) mirrors the CLI layout with `conversations/*.pb`; only `~/.gemini/antigravity-ide/antigravity_state.pbtxt` is readable — ignored.

## Decision

`GeminiActivityService` (new, `@Observable @MainActor`, replaces `refreshGemini()`) reads, every 5 min and on file change:
1. `conversation_summaries.db` opened read-only and immutable (`file:…?mode=ro&immutable=1`, via `/usr/bin/sqlite3` like the Codex reader in `ProviderUsageService`, or `SQLite3` C API — same approach as Codex for consistency) → `conversationsToday` (`last_user_input_time` today), `activeConversations` (`not_fully_idle = 1 AND killed = 0`), `agentsToday` (distinct non-empty `agent_name`), `workspacesToday` (distinct `workspace_uris`, last path component).
2. `history.jsonl` → `promptsToday` (timestamps ≥ start of day, local), `lastPromptAt`.
3. `antigravity-oauth-token` → `isLoggedIn` (file exists and non-empty).

Exposed as `GeminiActivity` value; **no token counts and no cost** — the card shows "activity", never "$". Dashboard Gemini card: prompts today, conversations today, active now, logged-in badge. Analytics › System: agents/workspaces list.

Alternatives: decoding protobuf blobs for model/tokens (best effort, breaks on every Antigravity update — rejected); calling a Google usage API (none available for Antigravity — not found).

## Error handling

| Situation | Behaviour |
|---|---|
| `antigravity-cli` dir missing | service inactive, card shows "Not installed" (as Codex does) |
| DB locked/busy | `immutable=1` avoids locks; on error keep last values, `lastError` |
| `history.jsonl` malformed lines | skipped |
| both IDE and CLI present | CLI only (IDE data is protobuf); documented |

## Testing

`GeminiActivityServiceTests` with a temp directory: build a small `conversation_summaries.db` via `sqlite3` in the test setup (schema above, 4 rows: today/yesterday/active/killed), a `history.jsonl` with 3 lines (2 today, 1 yesterday, 1 malformed), token file present/absent → assert counts; `startOfDay` injected. Pure parsing functions are `static` and tested directly.

## Out of scope

Token/cost figures for Gemini; Antigravity IDE conversations; Google AI Studio API keys.
