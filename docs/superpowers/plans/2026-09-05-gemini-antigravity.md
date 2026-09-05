# Gemini / Antigravity Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dead Gemini tracking (missing `oauth_creds.json`) with real activity figures read from the Antigravity CLI's local data: conversations and prompts today, active conversations, agents/workspaces, login state — no token or cost figures.

**Architecture:** `GeminiActivityService` (`@Observable @MainActor`) reads three sources under `~/.gemini/antigravity-cli/` every 5 min and on file change: `conversation_summaries.db` (SQLite, opened read-only/immutable through `/usr/bin/sqlite3` exactly like the Codex reader in `ProviderUsageService`), `history.jsonl`, and the presence of `antigravity-oauth-token`. Parsing is in pure static functions; the service only does I/O and publishing. The old `refreshGemini()` and `geminiTokenValid` are removed from `ProviderUsageService`.

**Tech Stack:** Swift 5.9, SwiftUI, SPM, XCTest with temp directories; `sqlite3` CLI (already used for Codex).

**Spec:** `docs/superpowers/specs/2026-09-05-gemini-antigravity-design.md`

**Verification (every task):** `swift build 2>&1 | grep -E "warning:.*\.swift|error:"` prints nothing; `swift test 2>&1 | grep -E "Executed [0-9]+ tests|Test run with" | tail -2` shows 0 failures.

---

## File structure

| File | Responsibility |
|---|---|
| `Sources/ClaudeBar/Models/GeminiActivity.swift` | `GeminiActivity` value (`conversationsToday`, `promptsToday`, `activeConversations`, `agentsToday: [String]`, `workspacesToday: [String]`, `lastPromptAt: Date?`, `isLoggedIn`) + pure parsers `GeminiActivityParser.parseSummaries(tsvRows:startOfDay:)` and `parseHistory(lines:startOfDay:)` |
| `Sources/ClaudeBar/Services/GeminiActivityService.swift` | I/O: locate directory, run `sqlite3` query, read `history.jsonl`, stat token file, publish `activity`, `isInstalled`, `lastError`; 5-min `ServiceTimer` + `FileWatcher` on `history.jsonl` |
| `Sources/ClaudeBar/Services/ProviderUsageService.swift` | remove `refreshGemini`, `geminiTokenValid`, `geminiCredsPath` |
| `Sources/ClaudeBar/Views/Dashboard/DashboardProviderSummary.swift`, `Sources/ClaudeBar/Views/Analytics/AnalyticsSystemPanel.swift` | Gemini card and system block |
| `Sources/ClaudeBar/AppDelegate.swift` | instantiate + `.environment(geminiActivityService)` in both chains |
| `Tests/ClaudeBarTests/GeminiActivityTests.swift`, `GeminiActivityServiceTests.swift` | tests |

---

### Task 1: `GeminiActivity` value and pure parsers

**Files:** create `Sources/ClaudeBar/Models/GeminiActivity.swift`; test `Tests/ClaudeBarTests/GeminiActivityTests.swift`.

The SQLite query (run by the service, Task 2) is:
```sql
SELECT conversation_id, last_user_input_time, last_modified_time, not_fully_idle, killed, agent_name, workspace_uris
FROM conversation_summaries;
```
executed with `sqlite3 -readonly -separator $'\t' "file:<path>?mode=ro&immutable=1"` → one TSV row per conversation. Times are ISO8601 strings (e.g. `2026-09-05 18:56:02.123456+02:00` or `2026-09-05T16:56:02Z` — accept both, `withFractionalSeconds` on and off, and the space separator); `not_fully_idle`/`killed` are `0`/`1`; `workspace_uris` is a JSON array of `file://` URIs or a single path.

- [ ] Failing tests:

```swift
import XCTest
@testable import ClaudeBarLib

final class GeminiActivityTests: XCTestCase {
    private let startOfDay = ISO8601DateFormatter().date(from: "2026-09-05T00:00:00+02:00")!

    func testParsesSummaryRows() {
        let rows = [
            "c1\t2026-09-05 10:00:00.5+02:00\t2026-09-05 10:05:00+02:00\t1\t0\tcoder\t[\"file:///Users/me/Dev/app\"]",
            "c2\t2026-09-04 23:59:59+02:00\t2026-09-05 00:10:00+02:00\t0\t0\t\t[\"file:///Users/me/Dev/old\"]",   // yesterday
            "c3\t2026-09-05T08:00:00Z\t2026-09-05T08:01:00Z\t1\t1\treviewer\t/Users/me/Dev/app",                    // killed → not active
            "c4\t2026-09-05 12:00:00+02:00\t2026-09-05 12:00:00+02:00\t0\t0\tcoder\t[]",
        ]
        let a = GeminiActivityParser.parseSummaries(tsvRows: rows, startOfDay: startOfDay)
        XCTAssertEqual(a.conversationsToday, 3)          // c1, c3, c4
        XCTAssertEqual(a.activeConversations, 1)         // c1 only (c3 killed)
        XCTAssertEqual(a.agentsToday, ["coder", "reviewer"])
        XCTAssertEqual(a.workspacesToday, ["app"])       // last path component, deduplicated, sorted
    }

    func testParsesHistoryLines() {
        let lines = [
            #"{"display":"hi","timestamp":1757066400000,"workspace":"/Users/me/Dev/app","conversationId":"c1"}"#,   // 2026-09-05 12:00 +02:00
            #"{"display":"old","timestamp":1756980000000,"workspace":"/Users/me/Dev/app"}"#,                        // yesterday
            #"not json"#,
            #"{"display":"again","timestamp":1757070000000,"workspace":"/Users/me/Dev/app","conversationId":"c1"}"#,
        ]
        let h = GeminiActivityParser.parseHistory(lines: lines, startOfDay: startOfDay)
        XCTAssertEqual(h.promptsToday, 2)
        XCTAssertEqual(h.lastPromptAt, Date(timeIntervalSince1970: 1_757_070_000))
    }
}
```

- [ ] Implement `GeminiActivity` (struct, `Sendable`, `Equatable`, all fields with defaults) and `enum GeminiActivityParser` with the two pure functions (`parseSummaries` returns a partial `GeminiActivity`; `parseHistory` returns `(promptsToday: Int, lastPromptAt: Date?)`). Date parsing helper `static func parseDate(_ s: String) -> Date?` tries: ISO8601 with/without fractional seconds, then the same after replacing the first space with `T`, then a `DateFormatter` `"yyyy-MM-dd HH:mm:ssXXXXX"` and `"yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX"` (`en_US_POSIX`).
- [ ] Commit `feat(gemini): add GeminiActivity model and Antigravity parsers.`

---

### Task 2: `GeminiActivityService`

**Files:** create `Sources/ClaudeBar/Services/GeminiActivityService.swift`; test `Tests/ClaudeBarTests/GeminiActivityServiceTests.swift`.

API:
```swift
@Observable @MainActor
final class GeminiActivityService {
    private(set) var isInstalled = false        // ~/.gemini/antigravity-cli exists
    private(set) var activity = GeminiActivity()
    private(set) var lastError: String?
    init(cliDirectory: URL = ~/.gemini/antigravity-cli, now: @escaping () -> Date = Date.init, disablePolling: Bool = false)
    func refresh() async                        // sqlite3 + history + token, off the main actor via Task.detached, then publish
}
```
- `sqlite3` invocation mirrors `ProviderUsageService.queryCodexDb` (Process, `/usr/bin/sqlite3`, `-readonly`, URI with `mode=ro&immutable=1`, 5 s timeout, stdout captured). Missing DB → summaries part empty, no error. Non-zero exit → `lastError = "sqlite3 exited <code>"`, keep previous activity.
- `history.jsonl` read fully (it is small) — if it grows beyond 5 MB read only the last 1 MB.
- `isLoggedIn` = `antigravity-oauth-token` exists with size > 0.
- Tests (temp dir; build a real DB in `setUp` with `sqlite3` using the schema from the spec and 4 rows mirroring Task 1; write `history.jsonl` with 3 lines; create/omit the token file): `testNotInstalledWithoutDirectory`, `testRefreshReadsAllThreeSources` (counts as in Task 1, `isLoggedIn == true`), `testMissingTokenMeansLoggedOut`, `testMissingDatabaseKeepsPromptsCount`, `testSqliteFailureKeepsPreviousActivity` (point `cliDirectory` at a dir whose `conversation_summaries.db` is a text file → error, activity unchanged).
- [ ] Commit `feat(gemini): read Antigravity CLI activity (conversations, prompts, login).`

---

### Task 3: Wire in, remove the dead Gemini code, UI

**Files:** `AppDelegate.swift`, `ProviderUsageService.swift` (+ its tests), `DashboardProviderSummary.swift`, `AnalyticsSystemPanel.swift`.

- [ ] Remove `refreshGemini()`, `geminiTokenValid`, `geminiCredsPath` and every consumer (`grep -rn "geminiTokenValid" Sources Tests`).
- [ ] Gemini card: when `!isInstalled` → "Antigravity not installed" (same style as Codex "not installed"); else "N prompts · M conversations today", "K active" badge when `activeConversations > 0`, and a "logged in / logged out" dot. Explicitly no `$` figure; card `.help("Antigravity does not expose token counts — activity only")`.
- [ ] Analytics › System: Gemini block with agents and workspaces of the day (comma-joined), last prompt (relative).
- [ ] Commit `feat(gemini): show Antigravity activity in Dashboard and Analytics.`

---

### Task 4: Docs and version

- [ ] README: Features › Dashboard bullet "**Gemini (Antigravity) activity** — prompts, conversations and active sessions today, login status (activity only: Antigravity does not expose tokens)"; How-It-Works row for `~/.gemini/antigravity-cli/{conversation_summaries.db,history.jsonl}`; Privacy: files listed, nothing sent.
- [ ] `CHANGELOG.md` `## [1.4.0] — <date>` Added / Removed (`oauth_creds.json` lookup); `VERSION` → `1.4.0`.
- [ ] Commit `docs: document Antigravity activity tracking.` then `chore(release): bump version to 1.4.0.`

---

## Self-review

Spec coverage: three sources ✔ (T1–T2), no cost ✔ (T3 wording), error table ✔ (T2 rules), UI ✔ (T3), tests ✔. Types: `GeminiActivity`, `GeminiActivityParser.parseSummaries/parseHistory/parseDate`, `GeminiActivityService.refresh/isInstalled/activity` used consistently.
