# Changelog

All notable changes to ClaudeBar are documented here.

## [Unreleased]

## [1.1.0] — 2026-09-05

### Fixed
- Cleared stale update state after failed checks or releases without ZIP assets.
- Made version comparison strict while supporting pre-release suffixes.
- Updated pricing for Claude Sonnet 5, Opus 5, and Fable 5.1.
- Corrected the 1M context window for Claude Opus 5 and Sonnet 5.
- Deduplicated streamed assistant chunks in project, yearly, and live token/cost statistics.
- Included nested sub-agent transcripts and filtered live statistics by each line's timestamp.
- Based burn-rate projections on today's first activity instead of time since midnight.
- Made self-updates transactional with rollback when installation fails.
- Replaced the running app bundle instead of always targeting `/Applications`.

### Changed
- Added conditional GitHub release checks and rate-limit backoff.
- CI now runs the unit test suite and fails when the build (not only `tee`) fails; committed `AppIcon.icns` so CI-built releases ship the app icon.
- Split `AnalyticsView`, `SettingsView` and `DashboardView` into per-panel files; centralised cost math in `CostCalculator`.
- README and CONTRIBUTING now describe the full feature set (Analytics window, oMLX, Codex/Gemini tracking, auto-update, export…).

## [1.0.13] — 2026-06-11

### Added
- **Claude Fable 5** support — pricing ($10/$50 per MTok), "Fable 5" display name, gold accent color, and 1M context window. Also covers Claude Mythos 5 (same pricing/limits).

## [1.0.12] — 2026-05-29

### Fixed
- **5h usage refresh** — the OAuth token refresh used an invalid `client_id`, so once the access token expired the refresh silently failed and the 5h window, forecast, and Dashboard rate-limit section all disappeared. Now uses Claude Code's public OAuth client ID, so refresh works again.

### Changed
- CI: bumped `actions/checkout` to v5 (Node 20 deprecation)

## [1.0.11] — 2026-05-29

### Added
- **5h-unavailable banner** — when the OAuth usage API returns no data, the Dashboard now shows the reason (e.g. "Token expired — refresh failed") instead of silently hiding the 5h section

### Changed
- **Menu bar indicator is now enabled by default**
- The menu bar no longer shows a bare "●" when 5h data is unavailable — it stays blank, and the Dashboard explains why

## [1.0.10] — 2026-05-29

### Added
- **Opus 4.8** pricing in the cost calculator
- **Menu bar 5h forecast** — the status bar indicator now shows the 5h limit forecast and reset countdown (e.g. `~1h38 → ↻2h10`, or `↻2h10` when usage is calm) instead of the daily cost in dollars

## [0.6.0] — 2026-04-09

### Added
- **Provider tracking** — Codex (SQLite) and Gemini (OAuth token) local usage indicators on the Dashboard
- **Cost alert threshold** — Configurable daily cost alert ($1–$50) in Settings › Display & Alerts
- **Usage-based icon tinting** — Brain icon turns orange/red when API usage is high (configurable)
- **Status bar indicator** — Opt-in: show cost or session count next to the menu bar icon

### Fixed
- Cost alert notification now works in SPM run mode (uses osascript fallback)
- 5h window projection hidden until 10% of the window has elapsed to avoid misleading values
- Environment variable masking now requires >12 chars before revealing suffix

## [0.5.0] — 2026-04-08

### Added
- **Token Ledger** — Per-message usage breakdown parsed from JSONL session files
- **Cmd+Shift+C** global hotkey to toggle the popover
- **CSV / JSON export** in Settings › Quick Actions
- **Optimization hints** — Dashboard tips when Opus usage is high or caching is low
- **Cache savings card** — Shows prompt caching ROI on the Dashboard
- **7-day project sparklines** — Mini activity chart on project cards

## [0.4.0] — 2026-03-20

### Added
- **Desktop widget** — Floating always-on-top panel (bottom-right, all Spaces)
- **Floating overlay** — PiP panel listing active sessions
- **Full analytics window** — Persistent resizable window with the same content as the popover
- **Anomaly detection** — Notification when daily spend exceeds 2× the 30-day average

## [0.3.0] — 2026-03-15

### Added
- **History view** — 30-day charts for cost, model breakdown, activity, and hourly heatmap
- **Stacked model cost chart** — Per-model daily cost breakdown
- **Projects view** — Per-project usage and cost aggregation

## [0.2.0] — 2026-03-10

### Added
- **Burn Rate card** — Cost/hr, projected daily cost, pacing zone vs. 30-day average
- **Human cost comparison** — Developer-hours equivalent and ROI multiplier
- **5h circular arc gauge** — Real-time Anthropic rate limit window visualization
- **MCP server health** — Checks all configured MCP servers in Settings
- **Hook health monitor** — Validates Claude Code hook configuration

## [0.1.0] — 2026-03-01

### Added
- Initial release: macOS menu bar app monitoring Claude Code usage
- Dashboard with today's cost, messages, sessions, tokens
- Active session list with context window estimation
- OAuth rate-limit data (5h and 7-day windows) via Anthropic API
- Settings view with Claude Code configuration viewer
- Zero third-party dependencies

[Unreleased]: https://github.com/BBerthod/ClaudeBar/compare/v1.0.12...HEAD
[1.0.12]: https://github.com/BBerthod/ClaudeBar/compare/v1.0.11...v1.0.12
[1.0.11]: https://github.com/BBerthod/ClaudeBar/compare/v1.0.10...v1.0.11
[1.0.10]: https://github.com/BBerthod/ClaudeBar/compare/v0.6.0...v1.0.10
[0.6.0]: https://github.com/BBerthod/ClaudeBar/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/BBerthod/ClaudeBar/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/BBerthod/ClaudeBar/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/BBerthod/ClaudeBar/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/BBerthod/ClaudeBar/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/BBerthod/ClaudeBar/releases/tag/v0.1.0
