# Contributing to ClaudeBar

Thank you for your interest in contributing!

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+ or Swift 5.9+ CLI
- An active Claude Code installation at `~/.claude` (needed for real data)

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
└── ContentView (SwiftUI tab container)
    ├── DashboardView  — today's cost, burn rate, sessions
    ├── HistoryView    — 30-day charts
    ├── ProjectsView   — per-project breakdown
    ├── SessionsView   — active/recent sessions
    └── SettingsView   — config viewer, notifications, quick actions

Services (@Observable, @MainActor)
├── StatsService       — reads ~/.claude/stats-cache.json
├── LiveStatsService   — parses JSONL when cache is stale
├── SessionService     — active session detection via PID
├── UsageService       — Anthropic OAuth API rate limits
├── BurnRateService    — cost/hr calculation and pacing
├── ProjectService     — per-project aggregation
├── NotificationService — alerts and daily digest
├── HookHealthService  — validates Claude Code hooks
├── McpHealthService   — MCP server connectivity
├── ProviderUsageService — Codex/Gemini local usage
└── AnomalyService     — spend anomaly detection
```

## Conventions

- **Zero third-party dependencies** — only Swift stdlib, AppKit, SwiftUI, and Charts
- **`@Observable` + `@MainActor`** for all services — no manual `objectWillChange`
- **`Task.detached`** for disk/process work (never block the main actor)
- **`weak self`** in all Timer and async closures
- No persistence layer — state is re-derived from files on every refresh

## Making Changes

1. Fork and create a branch: `git checkout -b feature/my-feature`
2. Build: `swift build -c release` (must compile without warnings)
3. Test manually with a real `~/.claude` directory
4. Open a pull request against `main`

## Pull Request Guidelines

- Keep PRs focused — one logical change per PR
- Update `CHANGELOG.md` under `[Unreleased]`
- Do not add third-party dependencies without discussion

## Reporting Issues

Open an issue on GitHub with:
- macOS version
- ClaudeBar version or commit hash
- Steps to reproduce
- Expected vs. actual behaviour
