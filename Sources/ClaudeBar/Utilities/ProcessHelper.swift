import AppKit
import Darwin

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

    /// Returns the parent PID of the given process using sysctl KERN_PROC,
    /// avoiding any subprocess spawn and blocking main-thread calls.
    private static func getParentPID(of pid: Int) -> Int? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        let result = sysctl(&mib, 4, &info, &size, nil, 0)
        guard result == 0 else { return nil }
        let ppid = Int(info.kp_eproc.e_ppid)
        return ppid > 0 ? ppid : nil
    }
}
