# CLAUDE.md

## Project
ClaudeBar is a macOS menu bar app (`LSUIElement`, no Dock icon) that monitors AI coding agents locally:
Claude Code (stats, sessions, costs, OAuth rate limits), Codex, Gemini/Antigravity CLI and the local oMLX server.
Data comes from local files (`~/.claude*`, `~/.codex`, `~/.gemini`, `~/.omlx`) and a few HTTPS endpoints listed in `README.md` › Privacy.

## Stack (actual versions)
- Swift tools 5.9 (`Package.swift`), macOS 14+ (`platforms: [.macOS(.v14)]`), SwiftUI + AppKit + Charts, Observation (`@Observable`).
- Swift Package Manager only, no Xcode project committed. Version in `VERSION` (currently 1.4.3).
- Zero runtime dependencies. Test-only dependency: `swift-snapshot-testing` (resolved 1.19.2).
- CI: GitHub Actions on `macos-15`. Builds and tests need macOS: AppKit does not compile on Linux.

## Commands
```bash
swift build                    # debug build (make build)
swift build -c release         # release build; CI fails on any "warning:"
make run                       # debug build + run .build/debug/ClaudeBar
make app                       # build/ClaudeBar.app (Info.plist via PlistBuddy, version from VERSION)
make install                   # app + copy to /Applications (kills the running instance)
swift test                     # all tests, including snapshots
swift test --skip SnapshotTests   # what CI runs
make catalog                   # regenerate Models/ModelCatalogSnapshot.swift from LiteLLM
make icon                      # regenerate Resources/AppIcon.icns
```
No linter or formatter is configured. The warnings-as-errors check in CI acts as the lint.

## Architecture
- `Sources/ClaudeBarApp/main.swift` → `runApp()` (`Sources/ClaudeBar/Bootstrap.swift`), the only `public` symbol.
  Everything else lives in the `ClaudeBarLib` target (`Sources/ClaudeBar`), which tests import with `@testable`.
- `AppDelegate.swift`: owns every service, the `NSStatusItem` + `NSPopover` (`ContentView` tabs: Dashboard, History,
  Projects, Sessions, Settings), the refresh/update/history timers, and injects services with `.environment(...)`.
- `Services/`: one `@Observable @MainActor final class` per concern (Stats, LiveStats, Session, Usage, BurnRate,
  Project, YearlyHistory, Notification, Anomaly, ProviderUsage, GeminiActivity, Omlx*, McpHealth, HookHealth,
  ModelCatalog, UpdateCheck, AutoUpdater, Settings, Export) plus window managers (MainWindow, DesktopWidget, Overlay).
- `Models/`: Codable/value types. `ModelCatalogSnapshot.swift` is **generated** (3.8k lines). Never edit it by hand.
- `Utilities/`: `CostCalculator`, `JSONLLines`/`JSONLLocator` (byte-level pre-filter + mmap JSONL scanning),
  `FileWatcher`, `ServiceTimer`, `ProcessHelper` (libproc/sysctl, no subprocess), `ScanProfiler`, `Log`.
- `Views/`: SwiftUI, split into `Dashboard/`, `Analytics/` (one file per panel), `Settings/`, `Components/`, `Theme/`.
- Key files: `AppDelegate.swift`, `Services/UsageService.swift` (Keychain + OAuth refresh),
  `Services/SessionService.swift`, `Services/ProjectService.swift`, `Services/AutoUpdater.swift`, `Views/Theme/Theme.swift`.

## Conventions observed
- Services: `@Observable` + `@MainActor`. Disk and process work runs in `Task.detached`, with `[weak self]` in timers and closures.
  Testable logic goes in `nonisolated static func` taking plain inputs (for example `ProjectService.scanWithModels(dirs:)`).
- Dependencies are injected through `init` (`URLSession`, directories, `now: () -> Date`, `CredentialStore`) for tests.
- Subprocesses: absolute executable path + argument array, never a shell. AppleScript receives data through `argv`.
- UI colors, spacing and radii come from `Theme` (`Theme.Space`, `Theme.Radius`, `Theme.color(_:)`), not literals.
- Logging: `Log.<category>` (`os.Logger`, subsystem `com.claudebar`). Never log tokens or API keys.
- Tests live in `Tests/ClaudeBarTests`: mostly XCTest, newer files use Swift Testing (`import Testing`, `#expect`).
  Fixtures are under `Fixtures/`, and snapshot PNGs under `__Snapshots__/` with perceptual precision 0.98.
- Commits: `type(scope): imperative summary.` with a trailing period (feat, fix, perf, refactor, style, docs, chore, ci).
- Every user-visible change gets an entry under `## [Unreleased]` in `CHANGELOG.md`.

## Gotchas
- `.gitignore` lists `CLAUDE.md` and `docs/plans/`, yet both are tracked. Edits are still tracked once a file is added.
- CI fails when `ModelCatalogSnapshot.generatedAt` is older than 90 days: run `make catalog` (next deadline 2026-12-04).
- `SettingsService.saveSettings` re-encodes `ClaudeSettings` and drops unmodelled keys of `~/.claude/settings.json`
  (see `docs/audit/2026-10-26-dette.md` D1). Do not add new writers on top of it.
- `UsageService` refreshes Claude Code's OAuth token and writes it back to the `Claude Code-credentials-*` Keychain
  item. Preserve the merge logic in `persistRefreshedToken`.
- The auto-updater runs at launch and every hour, replaces the bundle without prompting, and refuses to run from
  `.build/`, `build/`, `/tmp` or App Translocation (`AutoUpdater.isReplaceableBundle`).
- Snapshot tests depend on local text rasterisation. Re-record them on macOS only.
- Notifications fall back to `osascript` when the app runs as a bare SPM executable (no bundle).
- `CLAUDEBAR_PROFILE_FILE=<path>` enables the JSONL scan profiler (JSON lines, path hashes only).

## Release / deployment
No server and no Docker: distribution goes through GitHub Releases only.
- Bump `VERSION` + `CHANGELOG.md`, then merge to `main`. `.github/workflows/release.yml` builds `make app`, zips it and
  creates the `v<VERSION>` release if missing. Signing and notarization only run when the 5 secrets
  `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD` are set.
  Otherwise the build is unsigned.
- Installed apps pick up the new release through `UpdateCheckService` + `AutoUpdater` (first `.zip` asset of `releases/latest`).
- `.github/workflows/build.yml` (push and PR on `main`): catalog freshness, release build, no warnings, tests without snapshots.
