# Auto-Update System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the developer bumps `VERSION` and pushes to `main`, CI creates a GitHub Release; any running ClaudeBar downloads the new binary, silently replaces `/Applications/ClaudeBar.app`, and restarts.

**Architecture:** A `VERSION` file at the repo root is the single source of truth — read by `make app` (injected into `Info.plist`) and by the CI (used as the release tag). `UpdateCheckService` gains an injectable `URLSession` and a new `assetDownloadURL` property parsed from the GitHub API `assets` array. A new `AutoUpdater` service downloads the zip, extracts it, writes a shell update script (runs after the app quits), launches it, then calls `NSApp.terminate()`. `AppDelegate` adds an hourly timer and triggers `AutoUpdater` whenever an update is available.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, macOS 14+, URLSession, Foundation Process, XCTest + MockURLProtocol, GitHub Actions (`gh` CLI), GNU Make

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `VERSION` | Single source of truth for app version |
| Modify | `Makefile` | Read VERSION dynamically in `make app` target |
| Modify | `Sources/ClaudeBar/Services/UpdateCheckService.swift` | Add `assetDownloadURL`, injectable URLSession |
| Create | `Sources/ClaudeBar/Services/AutoUpdater.swift` | Download → extract → script → quit |
| Modify | `Sources/ClaudeBar/AppDelegate.swift` | Add `AutoUpdater`, hourly timer, install trigger |
| Create | `Tests/ClaudeBarTests/UpdateCheckServiceNetworkTests.swift` | Network tests for assetDownloadURL parsing |
| Create | `.github/workflows/release.yml` | Build and publish GitHub Release on main push |

---

### Task 1: VERSION file + Makefile dynamic version

**Files:**
- Create: `VERSION` (repo root)
- Modify: `Makefile`

**Why:** `make app` currently hardcodes `CFBundleShortVersionString = "1.0.0"` in `Info.plist`, so `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` always returns `"1.0.0"` at runtime regardless of what the developer intends. This task makes the version flow from one file through the entire pipeline.

- [ ] **Step 1: Create the VERSION file**

Create `VERSION` at the repository root with content:

```
1.0.0
```

No trailing newline, no extension. Verify:

```bash
cat VERSION
```
Expected: `1.0.0`

- [ ] **Step 2: Update the `app` target in Makefile**

In `Makefile`, replace the entire `app` target. The current target has two lines with hardcoded `string 1.0.0`. Replace the whole target with this (all recipe lines must start with a real TAB character):

```make
# Create .app bundle
app: release
	@VERSION=$$(cat VERSION); \
	echo "Bundling ClaudeBar.app v$$VERSION..."; \
	rm -rf build/ClaudeBar.app; \
	mkdir -p build/ClaudeBar.app/Contents/MacOS; \
	mkdir -p build/ClaudeBar.app/Contents/Resources; \
	cp .build/release/ClaudeBar build/ClaudeBar.app/Contents/MacOS/; \
	if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns build/ClaudeBar.app/Contents/Resources/; fi; \
	/usr/libexec/PlistBuddy \
		-c "Add :CFBundleIdentifier string io.github.claudebar" \
		-c "Add :CFBundleName string ClaudeBar" \
		-c "Add :CFBundleDisplayName string ClaudeBar" \
		-c "Add :CFBundleVersion string $$VERSION" \
		-c "Add :CFBundleShortVersionString string $$VERSION" \
		-c "Add :CFBundlePackageType string APPL" \
		-c "Add :CFBundleExecutable string ClaudeBar" \
		-c "Add :LSUIElement bool true" \
		-c "Add :LSMinimumSystemVersion string 14.0" \
		-c "Add :NSHighResolutionCapable bool true" \
		-c "Add :CFBundleIconFile string AppIcon" \
		build/ClaudeBar.app/Contents/Info.plist; \
	echo "✓ build/ClaudeBar.app v$$VERSION created"
```

**Makefile syntax note:** `$$VERSION` in Make = `$VERSION` in shell (double-`$` escapes Make's variable expansion). The `\` line continuation must have no trailing spaces.

- [ ] **Step 3: Verify make app embeds the correct version**

```bash
make app 2>&1 | tail -3
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/ClaudeBar.app/Contents/Info.plist
```
Expected:
```
✓ build/ClaudeBar.app v1.0.0 created
1.0.0
```

- [ ] **Step 4: Commit**

```bash
git add VERSION Makefile
git commit -m "feat(build): add VERSION file and inject version dynamically into Info.plist."
```

---

### Task 2: UpdateCheckService — assetDownloadURL + injectable URLSession

**Files:**
- Modify: `Sources/ClaudeBar/Services/UpdateCheckService.swift`
- Create: `Tests/ClaudeBarTests/UpdateCheckServiceNetworkTests.swift`

**Why:** The GitHub Releases API returns an `assets` array with `browser_download_url` for each uploaded file. Currently `UpdateCheckService` only reads `html_url` (the browser page), not the binary download URL. `AutoUpdater` needs the direct zip URL. We also inject `URLSession` so tests can mock network responses without hitting real APIs.

**GitHub API response shape:**
```json
{
  "tag_name": "v1.1.0",
  "html_url": "https://github.com/BBerthod/ClaudeBar/releases/tag/v1.1.0",
  "assets": [
    {
      "name": "ClaudeBar.zip",
      "browser_download_url": "https://github.com/BBerthod/ClaudeBar/releases/download/v1.1.0/ClaudeBar.zip"
    }
  ]
}
```

- [ ] **Step 1: Write failing tests**

Create `Tests/ClaudeBarTests/UpdateCheckServiceNetworkTests.swift`:

```swift
import XCTest
@testable import ClaudeBarLib

// MARK: - URLProtocol mock

private class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeResponse(status: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.github.com")!,
        statusCode: status, httpVersion: nil, headerFields: nil
    )!
}

// MARK: - Tests

@MainActor
final class UpdateCheckServiceNetworkTests: XCTestCase {

    /// Release with a zip asset → assetDownloadURL is set, updateAvailable is true
    func testAssetDownloadURLParsedWhenReleaseHasZipAsset() async throws {
        let responseData = """
        {
          "tag_name": "v1.1.0",
          "html_url": "https://github.com/BBerthod/ClaudeBar/releases/tag/v1.1.0",
          "assets": [
            {
              "name": "ClaudeBar.zip",
              "browser_download_url": "https://github.com/BBerthod/ClaudeBar/releases/download/v1.1.0/ClaudeBar.zip"
            }
          ]
        }
        """.data(using: .utf8)!
        MockURLProtocol.requestHandler = { _ in (makeResponse(), responseData) }

        let service = UpdateCheckService(currentVersion: "1.0.0", session: makeMockSession())
        await service.checkForUpdate()

        XCTAssertEqual(
            service.assetDownloadURL,
            "https://github.com/BBerthod/ClaudeBar/releases/download/v1.1.0/ClaudeBar.zip"
        )
        XCTAssertTrue(service.updateAvailable)
        XCTAssertEqual(service.latestVersion, "1.1.0")
    }

    /// Release with no assets → assetDownloadURL is nil, but updateAvailable may be true
    func testAssetDownloadURLNilWhenNoAssets() async throws {
        let responseData = """
        {
          "tag_name": "v1.1.0",
          "html_url": "https://github.com/BBerthod/ClaudeBar/releases/tag/v1.1.0",
          "assets": []
        }
        """.data(using: .utf8)!
        MockURLProtocol.requestHandler = { _ in (makeResponse(), responseData) }

        let service = UpdateCheckService(currentVersion: "1.0.0", session: makeMockSession())
        await service.checkForUpdate()

        XCTAssertNil(service.assetDownloadURL)
        XCTAssertTrue(service.updateAvailable)  // version is newer, but no downloadable asset
    }

    /// Same version → updateAvailable false, assetDownloadURL nil
    func testNoUpdateWhenVersionIsCurrent() async throws {
        let responseData = """
        {
          "tag_name": "v1.0.0",
          "html_url": "https://github.com/BBerthod/ClaudeBar/releases/tag/v1.0.0",
          "assets": [
            {
              "name": "ClaudeBar.zip",
              "browser_download_url": "https://github.com/BBerthod/ClaudeBar/releases/download/v1.0.0/ClaudeBar.zip"
            }
          ]
        }
        """.data(using: .utf8)!
        MockURLProtocol.requestHandler = { _ in (makeResponse(), responseData) }

        let service = UpdateCheckService(currentVersion: "1.0.0", session: makeMockSession())
        await service.checkForUpdate()

        XCTAssertNil(service.assetDownloadURL)
        XCTAssertFalse(service.updateAvailable)
    }

    /// Only first .zip asset URL is used (multiple assets → take the first zip)
    func testFirstZipAssetIsUsedWhenMultipleAssets() async throws {
        let responseData = """
        {
          "tag_name": "v2.0.0",
          "html_url": "https://github.com/BBerthod/ClaudeBar/releases/tag/v2.0.0",
          "assets": [
            {
              "name": "README.txt",
              "browser_download_url": "https://github.com/.../README.txt"
            },
            {
              "name": "ClaudeBar.zip",
              "browser_download_url": "https://github.com/.../ClaudeBar.zip"
            }
          ]
        }
        """.data(using: .utf8)!
        MockURLProtocol.requestHandler = { _ in (makeResponse(), responseData) }

        let service = UpdateCheckService(currentVersion: "1.0.0", session: makeMockSession())
        await service.checkForUpdate()

        XCTAssertEqual(service.assetDownloadURL, "https://github.com/.../ClaudeBar.zip")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter UpdateCheckServiceNetworkTests 2>&1 | tail -20
```
Expected: compilation failure — `UpdateCheckService.init(currentVersion:session:)` does not exist yet and `assetDownloadURL` is undefined.

- [ ] **Step 3: Update UpdateCheckService**

Replace the full content of `Sources/ClaudeBar/Services/UpdateCheckService.swift`:

```swift
import Foundation
import os

@Observable
@MainActor
final class UpdateCheckService {
    private(set) var latestVersion: String?
    private(set) var currentVersion: String
    private(set) var updateAvailable: Bool = false
    private(set) var releaseURL: String?
    /// Direct download URL for the release zip asset. Set only when a newer version is found
    /// and the release has a `.zip` asset attached.
    private(set) var assetDownloadURL: String?

    private let session: URLSession

    init(
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
        session: URLSession = .shared
    ) {
        self.currentVersion = currentVersion
        self.session = session
        Task { await checkForUpdate() }
    }

    func checkForUpdate() async {
        guard let url = URL(string: "https://api.github.com/repos/BBerthod/ClaudeBar/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else { return }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if isNewer(remote: remoteVersion, current: currentVersion) {
                latestVersion = remoteVersion
                releaseURL = htmlURL
                updateAvailable = true

                // Parse asset download URL (first .zip in assets array)
                if let assets = json["assets"] as? [[String: Any]],
                   let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                   let downloadURL = zipAsset["browser_download_url"] as? String {
                    assetDownloadURL = downloadURL
                }

                Log.stats.info("Update available: \(remoteVersion) (current: \(self.currentVersion))")
            } else {
                Log.stats.debug("ClaudeBar is up to date (\(self.currentVersion))")
            }
        } catch {
            // Silent failure — best-effort check
            Log.stats.debug("Update check failed silently: \(error.localizedDescription)")
        }
    }

    // MARK: - Semantic Version Comparison

    /// Returns true if `remote` is strictly newer than `current`.
    func isNewer(remote: String, current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(remoteParts.count, currentParts.count)
        for i in 0..<maxLength {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}
```

- [ ] **Step 4: Run all UpdateCheckService tests**

```bash
swift test --filter UpdateCheckServiceNetworkTests 2>&1 | tail -20
swift test --filter UpdateCheckServiceTests 2>&1 | tail -20
```
Expected: both suites pass — 4 network tests + 8 existing tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBar/Services/UpdateCheckService.swift \
        Tests/ClaudeBarTests/UpdateCheckServiceNetworkTests.swift
git commit -m "feat(update): expose assetDownloadURL and inject URLSession in UpdateCheckService."
```

---

### Task 3: AutoUpdater service

**Files:**
- Create: `Sources/ClaudeBar/Services/AutoUpdater.swift`

**Note:** No unit tests for `AutoUpdater`. The operations (URLSession download, Process unzip, shell script launch, NSApp.terminate) involve real system I/O that is verified by end-to-end integration (push a version, observe the update). Mocking NSApp.terminate in tests would require global state manipulation that adds more risk than value.

- [ ] **Step 1: Create `Sources/ClaudeBar/Services/AutoUpdater.swift`**

```swift
import AppKit
import Foundation
import os

/// Downloads a new ClaudeBar release zip, extracts it, and silently replaces
/// /Applications/ClaudeBar.app via a shell script that runs after the app quits.
@Observable
@MainActor
final class AutoUpdater {
    /// Guards against concurrent download/install cycles.
    private(set) var isUpdating: Bool = false

    private let supportDir: URL
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        supportDir = appSupport.appendingPathComponent("ClaudeBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    }

    /// Downloads the zip at `urlString`, extracts it, writes an update script,
    /// launches it, then calls `NSApp.terminate()`. Returns silently on any failure.
    func downloadAndInstall(from urlString: String) async {
        guard !isUpdating else { return }
        guard let url = URL(string: urlString) else {
            Log.stats.error("AutoUpdater: invalid URL — \(urlString)")
            return
        }

        isUpdating = true
        defer { isUpdating = false }

        let zipDest = supportDir.appendingPathComponent("update.zip")
        let extractDir = URL(fileURLWithPath: "/tmp/ClaudeBar-update")

        do {
            // 1. Download to a tmp path, then move to our Application Support dir
            Log.stats.info("AutoUpdater: downloading \(url.lastPathComponent)")
            let (tmpURL, _) = try await session.download(from: url)
            try? FileManager.default.removeItem(at: zipDest)
            try FileManager.default.moveItem(at: tmpURL, to: zipDest)

            // 2. Extract zip to /tmp/ClaudeBar-update/
            try? FileManager.default.removeItem(at: extractDir)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-q", zipDest.path, "-d", extractDir.path]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try unzip.run()
            unzip.waitUntilExit()

            guard unzip.terminationStatus == 0 else {
                Log.stats.error("AutoUpdater: unzip exited with status \(unzip.terminationStatus)")
                return
            }

            // 3. Verify the .app is present in the extracted directory
            let appPath = extractDir.appendingPathComponent("ClaudeBar.app")
            guard FileManager.default.fileExists(atPath: appPath.path) else {
                Log.stats.error("AutoUpdater: ClaudeBar.app not found in extracted zip at \(appPath.path)")
                return
            }

            // 4. Write a shell script that replaces the bundle after the app has quit.
            //    The script: sleeps 2s (app finishes termination), replaces the bundle, relaunches.
            let script = """
            #!/bin/sh
            sleep 2
            if [ -d "/tmp/ClaudeBar-update/ClaudeBar.app" ]; then
                mv "/Applications/ClaudeBar.app" "/Applications/ClaudeBar.app.bak" 2>/dev/null || true
                cp -R "/tmp/ClaudeBar-update/ClaudeBar.app" "/Applications/"
                rm -rf "/Applications/ClaudeBar.app.bak" 2>/dev/null || true
                open "/Applications/ClaudeBar.app"
            fi
            """
            let scriptURL = URL(fileURLWithPath: "/tmp/claudebar-update.sh")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )

            // 5. Launch the script detached (it will outlive the app), then quit
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
            launcher.arguments = [scriptURL.path]
            try launcher.run()

            Log.stats.info("AutoUpdater: update script launched — terminating for bundle replacement")
            NSApp.terminate(nil)

        } catch {
            Log.stats.error("AutoUpdater: update cycle failed — \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!` — no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeBar/Services/AutoUpdater.swift
git commit -m "feat(update): add AutoUpdater — download, extract, script-and-quit update flow."
```

---

### Task 4: AppDelegate — wire AutoUpdater + hourly check

**Files:**
- Modify: `Sources/ClaudeBar/AppDelegate.swift`

**Changes needed:**
1. Add `let autoUpdater = AutoUpdater()` service property
2. Add `private var updateCheckTimer: Timer?`
3. Add `startUpdateCheckTimer()` method (hourly repeat + 5s delayed initial trigger)
4. Add `installUpdateIfAvailable()` method
5. Call `startUpdateCheckTimer()` from `applicationDidFinishLaunching`
6. Invalidate `updateCheckTimer` in `applicationWillTerminate`

**Why 5 seconds delay:** `UpdateCheckService.init()` starts a `Task { await checkForUpdate() }`. That network call typically completes in 1–3 seconds. We wait 5 seconds after launch before calling `installUpdateIfAvailable()` to ensure the first check has finished.

- [ ] **Step 1: Add service property and timer variable**

In the services block (after `let updateCheckService = UpdateCheckService()`), add:

```swift
let autoUpdater = AutoUpdater()
private var updateCheckTimer: Timer?
```

Full context after the edit:
```swift
let updateCheckService = UpdateCheckService()
let autoUpdater = AutoUpdater()                  // ← ADD
let omlxMonitorService = OmlxMonitorService()

private var refreshTimer: Timer?
private var updateCheckTimer: Timer?             // ← ADD
private var globalHotkeyMonitor: Any?
```

- [ ] **Step 2: Add the two new methods**

Add these methods to `AppDelegate`, before `applicationWillTerminate`:

```swift
// MARK: - Auto-Update

private func startUpdateCheckTimer() {
    // Repeat hourly
    updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor in
            await self.updateCheckService.checkForUpdate()
            await self.installUpdateIfAvailable()
        }
    }
    // Initial trigger: wait 5s for the launch check (fired in UpdateCheckService.init) to settle
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
        guard let self else { return }
        Task { @MainActor in
            await self.installUpdateIfAvailable()
        }
    }
}

private func installUpdateIfAvailable() async {
    guard updateCheckService.updateAvailable,
          let url = updateCheckService.assetDownloadURL,
          !autoUpdater.isUpdating else { return }
    Log.stats.info("AppDelegate: triggering update to \(self.updateCheckService.latestVersion ?? "?")")
    await autoUpdater.downloadAndInstall(from: url)
}
```

- [ ] **Step 3: Call `startUpdateCheckTimer()` in `applicationDidFinishLaunching`**

After `setupGlobalHotkey()`, add one line:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    setupStatusItem()
    setupPopover()
    loadInitialData()
    startRefreshTimer()
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
        guard let self else { return }
        MainActor.assumeIsolated {
            self.restartRefreshTimer()
        }
    }
    setupGlobalHotkey()
    startUpdateCheckTimer()  // ← ADD THIS LINE
    let showDockIcon = UserDefaults.standard.bool(forKey: "claudebar.showDockIcon")
    NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
}
```

- [ ] **Step 4: Invalidate timer on terminate**

In `applicationWillTerminate`, add timer cleanup:

```swift
func applicationWillTerminate(_ notification: Notification) {
    if let monitor = globalHotkeyMonitor {
        NSEvent.removeMonitor(monitor)
        globalHotkeyMonitor = nil
    }
    updateCheckTimer?.invalidate()  // ← ADD THIS LINE
}
```

- [ ] **Step 5: Verify it compiles**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!` — no errors, no warnings.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeBar/AppDelegate.swift
git commit -m "feat(update): wire AutoUpdater and hourly check timer in AppDelegate."
```

---

### Task 5: GitHub Actions release workflow

**Files:**
- Create: `.github/workflows/release.yml`

**Why:** Currently `build.yml` only does a smoke build — it never publishes. Without published releases, `UpdateCheckService` hits the GitHub API and gets a 404 (no releases found) on every check. This workflow creates a GitHub Release with `ClaudeBar.zip` attached whenever the developer pushes a new `VERSION` to `main`.

**Idempotence:** If the same `VERSION` is pushed twice (e.g., re-push without version bump), the `gh release view` check detects the tag already exists and skips the release step — the workflow completes without error.

- [ ] **Step 1: Create `.github/workflows/release.yml`**

```yaml
name: Release

on:
  push:
    branches: [main]

# Required to create releases and upload assets
permissions:
  contents: write

jobs:
  release:
    name: Build and Publish Release
    runs-on: macos-14

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Read version from VERSION file
        id: version
        run: echo "version=$(cat VERSION)" >> "$GITHUB_OUTPUT"

      - name: Check if release already exists
        id: check
        run: |
          if gh release view "v${{ steps.version.outputs.version }}" > /dev/null 2>&1; then
            echo "exists=true" >> "$GITHUB_OUTPUT"
            echo "Release v${{ steps.version.outputs.version }} already exists — skipping."
          else
            echo "exists=false" >> "$GITHUB_OUTPUT"
            echo "Release v${{ steps.version.outputs.version }} does not exist — will create."
          fi
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Build .app bundle
        if: steps.check.outputs.exists == 'false'
        run: make app

      - name: Zip the app bundle
        if: steps.check.outputs.exists == 'false'
        run: |
          cd build
          zip -r ClaudeBar.zip ClaudeBar.app
          echo "Zip size: $(du -sh ClaudeBar.zip | cut -f1)"

      - name: Create GitHub Release with zip asset
        if: steps.check.outputs.exists == 'false'
        run: |
          gh release create "v${{ steps.version.outputs.version }}" \
            build/ClaudeBar.zip \
            --title "ClaudeBar v${{ steps.version.outputs.version }}" \
            --notes "Automated release from CI — push to main."
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 2: Validate YAML syntax**

```bash
python3 -c "
import yaml, sys
with open('.github/workflows/release.yml') as f:
    yaml.safe_load(f)
print('YAML valid')
" 2>&1
```
If `yaml` is not installed: `pip3 install pyyaml --quiet && python3 -c ...`

Expected: `YAML valid`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat(ci): add release.yml to publish GitHub Release on version bump."
```

---

## End-to-end verification

After all tasks are complete and the branch is merged to `main`:

**First release:**
1. Merge PR → CI runs `release.yml`
2. Verify at `https://github.com/BBerthod/ClaudeBar/releases` → release `v1.0.0` with `ClaudeBar.zip` attached

**First auto-update cycle:**
1. Edit `VERSION`: change `1.0.0` → `1.1.0`
2. Commit + push to `main`
3. CI creates release `v1.1.0`
4. Running ClaudeBar (installed at `v1.0.0`) detects the new version within ~1 hour (or on next launch)
5. App downloads `ClaudeBar.zip`, extracts it, runs the update script, restarts
6. Verify: right-click menu bar → version in window title or `defaults read /Applications/ClaudeBar.app/Contents/Info.plist CFBundleShortVersionString` returns `1.1.0`

---

## Self-Review Notes

- **Spec § VERSION file** → Task 1 ✅
- **Spec § Makefile dynamic** → Task 1 ✅
- **Spec § assetDownloadURL parsing** → Task 2 ✅
- **Spec § Injectable URLSession** → Task 2 ✅
- **Spec § AutoUpdater download/extract/script/quit** → Task 3 ✅
- **Spec § AppDelegate hourly timer** → Task 4 ✅
- **Spec § AppDelegate launch check (5s delay)** → Task 4 ✅
- **Spec § CI idempotent release** → Task 5 ✅
- **Spec § Silent UX** → Task 3 (no notifications, direct NSApp.terminate) ✅
- **Edge case: download failure** → `defer { isUpdating = false }` + catch block ✅
- **Edge case: unzip failure** → `terminationStatus != 0` guard ✅
- **Edge case: app not in zip** → `fileExists` guard before launching script ✅
- **Edge case: concurrent updates** → `isUpdating` debounce ✅
- **Edge case: same version** → `isNewer` returns false, nothing triggered ✅
- **No placeholder patterns found** ✅
- **Type consistency:** `downloadAndInstall(from: String)` matches in Task 3 definition and Task 4 call ✅; `assetDownloadURL: String?` matches in Task 2 definition and Task 4 usage ✅
