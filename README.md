# ClaudeBar

A macOS menu bar app for monitoring your [Claude Code](https://claude.ai/code) usage in real time.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![No dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

---

## Features

### Dashboard
- **Estimated cost** for today, with a live fallback when `stats-cache.json` hasn't updated yet
- **Stats grid** — messages, sessions, tool calls, and tokens
- **Token distribution** by model (Opus / Sonnet / Haiku) with a colour-coded bar
- **Rate limit gauges** — 5-hour and 7-day windows pulled directly from the Anthropic OAuth API, with pace indicators (Comfortable → Runaway)
- **Burn rate card** — cost/hr, projected daily cost, and pacing zone (Chill / On Track / Hot / Critical) compared to your 30-day average
- **Active sessions** with context-window usage estimate; click any session to jump to its terminal

### History
30-day activity charts for messages, sessions, tokens, and cost.

### Projects
Per-project usage and cost breakdown.

### Sessions
Active and recent session list. Tapping an active session focuses the terminal window running that Claude Code process.

### Settings
- Hook health monitor — checks that your `~/.claude/settings.json` hooks are correctly configured
- Notification preferences — daily digest (configurable hour) and cost threshold alerts

### Floating Overlay
A compact, always-on-top PiP panel listing active sessions. Toggle it with the pip button next to the tab bar. Draggable anywhere on screen, works across all Spaces.

---

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+ (for building from source)
- An active Claude Code installation at `~/.claude`

---

## Build & Run

ClaudeBar has **zero third-party dependencies** — only the Swift standard library, AppKit, and SwiftUI.

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

ClaudeBar reads data from three sources, in priority order:

| Source | What it provides |
|--------|-----------------|
| `~/.claude/stats-cache.json` | Primary stats — messages, sessions, tokens, model usage, 30-day history. File-watched for instant updates. |
| `~/.claude/projects/**/*.jsonl` | Live fallback — parsed directly when `stats-cache.json` has no entry for today. Deduplicates by message ID. |
| Anthropic OAuth API | Real-time rate limit data (5h / 7d windows). OAuth token read from the system Keychain (`Claude Code-credentials`). Polled every 60 s. |

Active sessions are detected by scanning `~/.claude/sessions/` and confirming each stored PID is still alive.

---

## Architecture

```
AppDelegate (pure AppKit)
├── NSStatusItem  ← menu bar icon
└── NSPopover     ← SwiftUI content (420 × 520 pt)
    └── ContentView (tab bar)
        ├── DashboardView
        ├── HistoryView
        ├── ProjectsView
        ├── SessionsView
        └── SettingsView

OverlayManager  ← floating NSPanel (always-on-top)
```

All services use the `@Observable` macro (Swift 5.9 / iOS 17 / macOS 14 observation model) and run on `@MainActor`. There is no persistence layer — state lives in memory and is re-derived from files on every refresh cycle (30-second timer + file watching).

### Services

| Service | Responsibility |
|---------|---------------|
| `StatsService` | Reads and watches `stats-cache.json` |
| `LiveStatsService` | Parses today's JSONL files when cache is stale |
| `SessionService` | Active and recent session detection + context estimation |
| `UsageService` | OAuth API rate-limit fetch + Keychain token management |
| `BurnRateService` | Hourly cost rate, end-of-day projection, pacing zone |
| `ProjectService` | Per-project cost aggregation |
| `HookHealthService` | Validates Claude Code hook configuration |
| `NotificationService` | Cost threshold alerts and daily digest notifications |
| `OverlayManager` | Floating PiP panel lifecycle |

---

## Privacy

ClaudeBar never sends your usage data anywhere. All processing happens locally:

- Stats are read from `~/.claude` on your machine
- The only outbound network call is to `api.anthropic.com/api/oauth/usage` using your own existing OAuth token, to fetch your rate-limit state

---

## License

MIT
