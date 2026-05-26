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
        // Script in supportDir (user-only writable) — avoids /tmp TOCTOU race
        let scriptURL = supportDir.appendingPathComponent("claudebar-update.sh")

        do {
            // 1. Download to tmp path, then move to Application Support
            Log.stats.info("AutoUpdater: downloading \(url.lastPathComponent)")
            let (tmpURL, _) = try await session.download(from: url)

            // 2. File I/O and extraction off MainActor (avoids blocking main thread)
            let terminationStatus: Int32 = try await Task.detached(priority: .utility) {
                try? FileManager.default.removeItem(at: zipDest)
                try FileManager.default.moveItem(at: tmpURL, to: zipDest)

                try? FileManager.default.removeItem(at: extractDir)
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip.arguments = ["-q", zipDest.path, "-d", extractDir.path]
                unzip.standardOutput = FileHandle.nullDevice
                unzip.standardError = FileHandle.nullDevice
                try unzip.run()
                unzip.waitUntilExit()
                return unzip.terminationStatus
            }.value

            guard terminationStatus == 0 else {
                Log.stats.error("AutoUpdater: unzip exited with status \(terminationStatus)")
                return
            }

            // 3. Verify .app exists (off MainActor)
            let appPath = extractDir.appendingPathComponent("ClaudeBar.app")
            let appExists = await Task.detached(priority: .utility) {
                FileManager.default.fileExists(atPath: appPath.path)
            }.value

            guard appExists else {
                Log.stats.error("AutoUpdater: ClaudeBar.app not found in extracted zip at \(appPath.path)")
                return
            }

            // 4. Write update script to supportDir (user-only writable, no TOCTOU risk)
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
            try await Task.detached(priority: .utility) {
                try script.write(to: scriptURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: scriptURL.path
                )
            }.value

            // 5. Launch script detached, then quit (back on MainActor)
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
