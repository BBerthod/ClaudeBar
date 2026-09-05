# ClaudeBar

A macOS menu bar app for monitoring your [Claude Code](https://claude.ai/code) usage in real time.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![Zero runtime dependencies](https://img.shields.io/badge/dependencies-0%20runtime-brightgreen)

---

## Features

### Menu Bar
- **Brain icon** tinted by 5-hour usage (neutral → orange → red)
- **5h forecast indicator** (on by default) — shows the estimated time to the 5-hour limit and the reset countdown next to the icon, e.g. `~1h38 → ↻2h10` when you're on pace to hit the limit, or `↻2h10` when usage is calm. Toggle it in Settings › Display & Alerts.

### Dashboard
- **Estimated cost** for today, with a live fallback when `stats-cache.json` hasn't updated yet
- **7-day sparkline** — mini activity chart in the header showing the last week's message trend
- **Stats grid** — messages, sessions, tool calls, and tokens
- **Token distribution** across active models (Fable, Opus, Sonnet, Haiku tiers) with a colour-coded bar
- **5h usage gauge** — circular gauge showing real-time 5-hour window utilization with color gradient (green → red) and pace indicator
- **Rate limit bars** — 7-day and Sonnet windows pulled directly from the Anthropic OAuth API
- **Burn rate card** — cost/hr, projected daily cost, and pacing zone (Chill / On Track / Hot / Critical) compared to your 30-day average
- **Human cost comparison** — estimated equivalent developer hours and cost, with ROI multiplier badge
- **Active sessions** with context-window usage estimate; click any session to jump to its terminal
- **Multi-provider tracking** — status cards for Claude, Gemini (OAuth token status), Codex (sessions, tokens, and context limits from local logs), and oMLX (local inference server health and active model)

### History
- **30-day activity charts** for messages, sessions, tokens, and cost
- **Yearly contribution graph** — GitHub-style 52-week heatmap showing daily token or cost activity across all profiles and projects over the past year

### Projects
Per-project usage and cost breakdown aggregated across all `~/.claude*` profiles.

### Sessions
- **Active and recent sessions** — tapping an active session focuses the terminal window running that Claude Code process
- **Quick resume bar** — search and autocomplete recent sessions by project, git branch, or summary, with one-click copy of `claude --resume <sessionId>` to clipboard

### Settings
- **Hook health monitor** — checks that your `settings.json` hooks are correctly configured
- **MCP health check** — validates reachability and status of configured Model Context Protocol servers in `~/.claude.json` (stdio and HTTP)
- **Notification preferences** — daily digest (configurable hour), cost threshold alerts, and context compaction alerts
- **Usage threshold alerts** — automatic notifications at 80% and 95% of the 5-hour rate limit window, with per-reset-window deduplication
- **Spend anomaly alerts** — automatic alerts when daily spend exceeds 2× the 30-day average baseline
- **Launch at Login** — starts ClaudeBar automatically at user login via `SMAppService`
- **Data export** — export historical usage data, tokens, and costs to CSV or JSON
- **Auto-updates** — background update checks against GitHub Releases with silent installation

### Analytics Window
A dedicated 1024 × 768 pt window (`NavigationSplitView`) opened via the window button in the popover header, featuring seven specialized views:
- **Alerts** — active critical, warning, and info alerts across rate limits, context windows, and spend anomalies
- **Trends** — multi-metric activity trends and visualizations
- **Projects** — detailed per-project token usage, cost estimates, and session history
- **Sessions** — deep inspection of session contexts and activity
- **Models** — 30-day token distribution breakdown across model tiers
- **Savings** — developer hours equivalent and estimated cost savings with ROI analysis
- **System** — app diagnostics, account plan & rate tier, cache freshness, MCP server health, and local oMLX inference metrics

### Floating Overlay
A compact, always-on-top PiP panel listing active sessions. Draggable anywhere on screen, works across all Spaces.

### Desktop Widget
A floating always-on-top panel showing at a glance: 5-hour usage gauge, today's tokens, active session count, and estimated cost. Positioned at the bottom-right of the screen, works across all Spaces.

---

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+ (for building from source)
- An active Claude Code installation (`~/.claude`, with automatic detection and multi-profile support across `~/.claude*`)

---

## Build & Run

ClaudeBar has **zero third-party runtime dependencies** — only the Swift standard library, AppKit, and SwiftUI (with a single test dependency, `swift-snapshot-testing`).

```bash
git clone https://github.com/BBerthod/ClaudeBar
cd ClaudeBar
swift build -c release
swift run
```

Or open in Xcode:

```bash
open Package.swift
```

---

## How It Works

ClaudeBar automatically discovers and aggregates data across all `~/.claude*` configuration directories on your machine, scoring candidate directories based on recent activity and `settings.json` to identify the active profile.

Data is gathered from the following sources, in priority order:

| Source | What it provides |
|--------|-----------------|
| LiteLLM model catalog | Pricing and context windows for Claude, OpenAI and Gemini models, refreshed daily (bundled snapshot as fallback). Unknown models are estimated from their family and flagged "~". |
| `~/.claude*/stats-cache.json` | Primary stats — messages, sessions, tokens, model usage, 30-day history. Auto-detects active directory and file-watched for instant updates. |
| `~/.claude*/projects/**/*.jsonl` | Live fallback & project aggregation — parsed directly across all profile directories when cache is stale. Deduplicates by message ID. |
| Anthropic OAuth API | Real-time rate limit data (5h / 7d windows). OAuth token read from the system Keychain (`Claude Code-credentials`). Polled every 5 min. Auto-refreshes expired tokens via the OAuth refresh flow. |
| Local Provider Logs | Codex sessions, tokens, and context limits from `~/.codex/logs_N.sqlite`; Gemini auth status from `~/.gemini/oauth_creds.json`. |
| Local oMLX Server | Status, engine pool memory, and loaded models polled from `http://127.0.0.1:8000/health`. |

Active sessions are detected by scanning `~/.claude*/sessions/` and confirming each stored PID is still alive.

---

## Architecture

```
AppDelegate (pure AppKit)
├── NSStatusItem       ← menu bar icon
├── NSPopover          ← SwiftUI content (420 × 520 pt)
│   └── ContentView (tab bar)
│       ├── DashboardView
│       ├── HistoryView
│       ├── ProjectsView
│       ├── SessionsView
│       └── SettingsView
├── MainWindowManager  ← standalone Analytics window (1024 × 768 pt)
│   └── AnalyticsView (Alerts, Trends, Projects, Sessions, Models, Savings, System)
├── DesktopWidgetManager ← floating desktop HUD NSPanel (DesktopWidgetView)
└── OverlayManager     ← floating PiP session NSPanel (FloatingOverlay)
```

All services use the `@Observable` macro (Swift 5.9 / iOS 17 / macOS 14 observation model) and run on `@MainActor`. There is no persistence layer — state lives in memory and is re-derived from files on every refresh cycle (30-second timer + file watching).

### Services

| Service | Responsibility |
|---------|---------------|
| `StatsService` | Reads and watches `stats-cache.json` |
| `LiveStatsService` | Parses today's JSONL files when cache is stale |
| `SessionService` | Active and recent session detection + context estimation |
| `UsageService` | OAuth API rate-limit fetch, Keychain token management, auto-refresh |
| `BurnRateService` | Hourly cost rate, end-of-day projection, pacing zone |
| `ProjectService` | Per-project cost aggregation across all `~/.claude*` directories |
| `HookHealthService` | Validates Claude Code hook configuration |
| `McpHealthService` | Validates configured MCP server connectivity (`~/.claude.json`) |
| `ProviderUsageService` | Tracks local Codex and Gemini usage and token metrics |
| `OmlxMonitorService` | Polls local oMLX inference server health, models, and memory |
| `AnomalyService` | Spend anomaly detection (flags daily spend ≥ 2× 30-day average) |
| `YearlyHistoryService` | 365-day token and cost history across profiles for heatmap & trends |
| `NotificationService` | Cost threshold alerts, usage threshold alerts (80%/95%), daily digest |
| `AutoUpdater` | Background download and in-place app replacement for GitHub Releases |
| `UpdateCheckService` | Checks GitHub Releases API for new versions |
| `LaunchAtLoginService` | Manages login item registration via `SMAppService` |
| `ExportService` | Exports stats data to CSV or JSON via `NSSavePanel` |
| `OverlayManager` | Floating PiP session panel lifecycle |
| `DesktopWidgetManager` | Floating desktop widget panel lifecycle |
| `MainWindowManager` | Standalone analytics window lifecycle |
| `SettingsService` | Reads and watches Claude Code configuration from `settings.json` |

---

## Privacy

ClaudeBar never sends your usage data anywhere. All processing happens locally:

- Stats are read from local `~/.claude*`, `~/.codex`, and `~/.gemini` files on your machine
- The only outbound network calls are to:
  - `api.anthropic.com/api/oauth/usage` (rate-limit data) and `console.anthropic.com/v1/oauth/token` (token refresh), both using your existing OAuth credentials
  - `api.github.com/repos/BBerthod/ClaudeBar/releases/latest` (version check for updates)
  - `raw.githubusercontent.com` (LiteLLM model catalog download; no usage data sent)
  - `http://127.0.0.1:8000/health` (local oMLX inference health monitoring, entirely on localhost)

---

## License

MIT
