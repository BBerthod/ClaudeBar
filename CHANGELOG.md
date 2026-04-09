# Changelog

All notable changes to ClaudeBar are documented here.

## [Unreleased]

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

[Unreleased]: https://github.com/BBerthod/ClaudeBar/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/BBerthod/ClaudeBar/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/BBerthod/ClaudeBar/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/BBerthod/ClaudeBar/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/BBerthod/ClaudeBar/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/BBerthod/ClaudeBar/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/BBerthod/ClaudeBar/releases/tag/v0.1.0
