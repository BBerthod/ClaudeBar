import Foundation

/// Opt-in scan profiler. Fully off unless env CLAUDEBAR_PROFILE_FILE is set.
/// Output: JSON lines with labels, timings, sizes and opaque path hashes only —
/// never a path, a project name or any file content.
enum ScanProfiler {
    private nonisolated static let lock = NSLock()

    /// Read once: the environment cannot change during the process lifetime, and this is
    /// checked for every file the scanners read.
    private nonisolated static let cachedOutputPath: String? = {
        guard let path = ProcessInfo.processInfo.environment["CLAUDEBAR_PROFILE_FILE"],
              !path.isEmpty else {
            return nil
        }
        return path
    }()

    nonisolated static var outputPath: String? { cachedOutputPath }

    nonisolated static var isEnabled: Bool {
        outputPath != nil
    }

    /// event is "begin" or "end". Appends {"kind":"mark","label":..,"event":..,"t":..}
    nonisolated static func mark(_ label: String, _ event: String) {
        guard isEnabled else { return }
        append([
            "kind": "mark",
            "label": label,
            "event": event,
            "t": ProcessInfo.processInfo.systemUptime,
        ])
    }

    /// Appends {"kind":"file","label":..,"fileKey":"<opaque hash of path>","bytes":..,"t":..}
    nonisolated static func recordFile(label: String, path: String, bytes: Int) {
        guard isEnabled else { return }
        append([
            "kind": "file",
            "label": label,
            "fileKey": String(path.hashValue),
            "bytes": bytes,
            "t": ProcessInfo.processInfo.systemUptime,
        ])
    }

    private nonisolated static func append(_ object: [String: Any]) {
        guard let outputPath,
              var data = try? JSONSerialization.data(withJSONObject: object) else {
            return
        }
        data.append(0x0A)

        lock.lock()
        defer { lock.unlock() }

        if !FileManager.default.fileExists(atPath: outputPath) {
            FileManager.default.createFile(atPath: outputPath, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: outputPath)) else {
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }
}
