import AppKit

enum ProcessHelper {
    /// Attempt to bring the terminal window containing the given PID to the front.
    static func focusTerminal(forChildPID pid: Int) {
        // Walk up the process tree to find a GUI app
        var currentPid = pid
        for _ in 0..<5 { // max 5 levels up
            guard let parentPid = getParentPID(of: currentPid) else { break }
            if let app = NSRunningApplication(processIdentifier: pid_t(parentPid)),
               app.activationPolicy == .regular {
                app.activate()
                return
            }
            currentPid = parentPid
        }

        // Fallback: try common terminal apps
        let terminalBundleIds = [
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "dev.zed.Zed",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92"  // Ghostty
        ]
        for bundleId in terminalBundleIds {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if let app = apps.first {
                app.activate()
                return
            }
        }
    }

    private static func getParentPID(of pid: Int) -> Int? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "ppid=", "-p", "\(pid)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let ppid = Int(output) {
                return ppid
            }
        } catch {}
        return nil
    }
}
