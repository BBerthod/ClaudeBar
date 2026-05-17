import Foundation

/// Detects the active Claude Code configuration directory by scanning the home directory.
///
/// GUI apps do not inherit shell environment variables (e.g. `CLAUDE_CONFIG_DIR`), so the
/// standard `~/.claude` default may not match the user's actual config location.  This
/// detector scores each candidate directory and returns the best match.
///
/// Scoring rules:
///   +10  `settings.json` exists inside the candidate
///   +5   `projects/` subdirectory exists
///   +20  `projects/` was modified within the last 24 hours
///   +10  `projects/` was modified within the last 7 days (mutually exclusive with +20)
enum ClaudeDirectoryDetector {

    /// Returns the absolute path of the most likely Claude config directory.
    /// Never returns `nil` — falls back to `"~/.claude"` when nothing is found.
    static func detect() -> String {
        let home = NSHomeDirectory()
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: home) else {
            return "~/.claude"
        }

        // Collect candidate directory names that match the pattern
        let candidates = entries.filter { name in
            name == ".claude" || name.hasPrefix(".claude-")
        }

        guard !candidates.isEmpty else {
            return "~/.claude"
        }

        var best: (path: String, score: Int) = ("", 0)
        let now = Date()
        let oneDay: TimeInterval = 86_400
        let oneWeek: TimeInterval = 604_800

        for name in candidates {
            let path = (home as NSString).appendingPathComponent(name)

            // Only consider directories
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            var score = 0

            // +10 if settings.json exists
            let settingsPath = (path as NSString).appendingPathComponent("settings.json")
            if fm.fileExists(atPath: settingsPath) {
                score += 10
            }

            // +5/+20/+10 based on projects/ directory
            let projectsPath = (path as NSString).appendingPathComponent("projects")
            var projIsDir: ObjCBool = false
            if fm.fileExists(atPath: projectsPath, isDirectory: &projIsDir), projIsDir.boolValue {
                score += 5

                if let attrs = try? fm.attributesOfItem(atPath: projectsPath),
                   let modDate = attrs[.modificationDate] as? Date {
                    let age = now.timeIntervalSince(modDate)
                    if age <= oneDay {
                        score += 20
                    } else if age <= oneWeek {
                        score += 10
                    }
                }
            }

            if score > best.score {
                best = (path, score)
            }
        }

        if best.score == 0 || best.path.isEmpty {
            return "~/.claude"
        }

        return best.path
    }
}
