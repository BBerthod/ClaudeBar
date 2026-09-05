# Contributing to ClaudeBar

Thank you for your interest in contributing!

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+ or Swift 5.9+ CLI
- An active Claude Code installation (`~/.claude` or `~/.claude-*` directories, needed for real data)

## Getting Started

```bash
git clone https://github.com/BBerthod/ClaudeBar
cd ClaudeBar
swift build
swift run
```

Or open in Xcode:

```bash
open Package.swift
```

## Architecture

```
AppDelegate (AppKit, @MainActor)
├── NSStatusItem + NSPopover
│   └── ContentView (SwiftUI tab container)
│       ├── DashboardView        — today's cost, burn rate, sessions, provider cards
│       ├── HistoryView          — 30-day charts and yearly contribution heatmap
│       ├── ProjectsView         — per-project breakdown across profiles
│       ├── SessionsView         — active/recent sessions and quick resume bar
│       └── SettingsView         — config viewer, notifications, MCP, export, launch at login
├── MainWindowManager
│   └── AnalyticsView            — standalone window (Alerts, Trends, Projects, Sessions, Models, Savings, System)
├── DesktopWidgetManager
│   └── DesktopWidgetView        — floating desktop HUD panel
└── OverlayManager
    └── FloatingOverlay          — floating PiP active sessions panel

View Components (Views/Components/)
├── ContextGauge.swift           — circular context window utilization gauge
├── ContributionGraph.swift      — 52-week GitHub-style activity grid (tokens / cost)
├── HourGridView.swift           — hourly activity heatmap
├── QuickResumeBar.swift         — fuzzy session search with one-click resume copy
├── SessionRow.swift             — active and recent session rows
├── Sparkline.swift              — 7-day trend sparkline chart
├── StatCard.swift               — key metric card with trend indicators
└── TokenBar.swift               — color-coded model token distribution bar

Services (@Observable, @MainActor)
├── StatsService          — reads and watches ~/.claude/stats-cache.json
├── LiveStatsService      — parses JSONL when stats cache is stale
├── SessionService        — active session detection via PID and context estimation
├── UsageService          — Anthropic OAuth API rate limits and token refresh
├── BurnRateService       — cost/hr calculation, daily projection, and pacing zones
├── ProjectService        — per-project aggregation across ~/.claude*
├── NotificationService   — alerts (thresholds, cost, context) and daily digest
├── HookHealthService     — validates Claude Code hooks configuration
├── McpHealthService      — validates MCP server connectivity (~/.claude.json)
├── ProviderUsageService  — Codex and Gemini local usage and token metrics
├── OmlxMonitorService    — local oMLX inference server health & models
├── AnomalyService        — spend anomaly detection (≥ 2× 30-day baseline)
├── YearlyHistoryService  — 365-day history and contribution heatmap across all profiles
├── UpdateCheckService    — GitHub Releases API update checker
├── AutoUpdater           — background download and in-place app replacement
├── ExportService         — CSV and JSON data export via NSSavePanel
├── LaunchAtLoginService  — SMAppService login item management
├── DesktopWidgetManager  — floating desktop widget panel lifecycle
├── OverlayManager        — floating PiP session overlay lifecycle
├── MainWindowManager     — standalone analytics window lifecycle
└── SettingsService       — reads Claude Code settings.json
```

## Conventions

- **Zero runtime dependencies** — only Swift stdlib, AppKit, SwiftUI, and Charts (one test dependency: `swift-snapshot-testing`)
- **`@Observable` + `@MainActor`** for all services — no manual `objectWillChange`
- **`Task.detached`** for disk/process work (never block the main actor)
- **`weak self`** in all Timer and async closures
- No persistence layer — state is re-derived from files on every refresh

## Testing

Run the test suite locally:

```bash
swift test
```

- **Snapshot testing**: View snapshots (`StatCard`, `Sparkline`, `ContributionGraph`) are powered by `swift-snapshot-testing` with a `0.98` perceptual precision tolerance (`assertSnapshot(..., as: .image(perceptualPrecision: 0.98))`).
- **CI test execution**: In CI (`.github/workflows/build.yml`), snapshot tests are excluded via:
  ```bash
  swift test --skip SnapshotTests
  ```
  Snapshot tests depend on exact macOS text rasterization and are validated locally.
- **Compiler warnings**: The CI build workflow treats warnings as fatal (`warning:` detected in build logs fails the workflow). Make sure release builds compile cleanly:
  ```bash
  swift build -c release
  ```

## Making Changes

1. Fork and create a branch: `git checkout -b feature/my-feature`
2. Build and test: `swift build -c release` (must compile without warnings) and `swift test`
3. Test manually with real `~/.claude*` directories
4. Open a pull request against `main`

## Pull Request Guidelines

- Keep PRs focused — one logical change per PR
- Update `CHANGELOG.md` under `[Unreleased]`
- Do not add third-party runtime dependencies without discussion

## Release Process

Releases are automated via GitHub Actions (`.github/workflows/release.yml`):

1. Update the version string in the `VERSION` file and push to `main`.
2. The workflow verifies the release tag `vX.Y.Z` does not already exist, builds the application bundle (`make app`), archives it into `ClaudeBar.zip`, and publishes a GitHub Release with the zip asset attached.
3. Installed ClaudeBar apps automatically check for updates against the GitHub API (`https://api.github.com/repos/BBerthod/ClaudeBar/releases/latest`) on startup and hourly (`UpdateCheckService`). When a newer release is found, `AutoUpdater` downloads the zip, extracts the `.app` bundle, and swaps in the new bundle in place of the running app (with rollback if the copy fails), then relaunches.

## Reporting Issues

Open an issue on GitHub with:
- macOS version
- ClaudeBar version or commit hash
- Steps to reproduce
- Expected vs. actual behaviour
