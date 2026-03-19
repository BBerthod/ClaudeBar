# ClaudeBar — Hybrid Window Design

## Summary

Add a persistent, resizable main window alongside the existing menu bar popover. The popover stays compact (420×520) for daily quick glance. The main window (1024×768+) provides space for Smart Alerts and Usage Analytics.

## Architecture

```
Menu Bar Icon (click → popover, ⌘+click → main window)
├── NSPopover (420×520) — existing, unchanged
│   └── ContentView (5 tabs: Dash, History, Projects, Sessions, Settings)
└── NSWindow (1024×768, resizable) — NEW
    └── AnalyticsView
        ├── Smart Alerts panel
        ├── Cost trends (weekly comparison, day-over-day)
        ├── ROI by project
        └── Max plan savings calculator
```

## Components

### MainWindowManager
- Similar pattern to OverlayManager/DesktopWidgetManager
- Creates NSWindow on demand, reuses on subsequent opens
- Window persists when closed (orderOut, not destroy)
- Resizable with minimum size 800×500

### AnalyticsView (new SwiftUI view)
- Sidebar navigation (not tabs — more space)
- Sections: Alerts, Trends, Projects, Export
- Receives same service instances as ContentView (shared @Observable state)

### Smart Alerts
- Context window > 80% on any active session
- Daily cost exceeds 2× rolling average
- 5h rate limit projected to hit 100%
- MCP server down (from McpHealthService)
- Stats-cache stale > 24h

### Usage Analytics
- Weekly cost trend (bar chart, current week vs previous)
- Day-over-day comparison
- ROI per project (dev-hours saved / Claude cost)
- "Max plan savings" = API equivalent cost - $200/month
- Export to CSV

## Entry Points
1. Button in popover header "Open Dashboard ↗"
2. ⌘+click on menu bar icon
3. Quick Action button in Settings

## Implementation: ~100 lines for window manager, ~400 for AnalyticsView
