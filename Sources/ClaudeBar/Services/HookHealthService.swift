import Foundation

@Observable
@MainActor
final class HookHealthService {
    private(set) var hookEntries: [HookHealthEntry] = []

    var totalHookTypes: Int { hookEntries.count }

    var totalHooks: Int {
        hookEntries.reduce(0) { $0 + $1.totalHooks }
    }

    var issueCount: Int {
        hookEntries
            .flatMap { $0.scriptStatuses.values }
            .filter { $0 == .missing || $0 == .notExecutable }
            .count
    }

    // MARK: - Public API

    func analyze(settings: ClaudeSettings?) {
        guard let hooks = settings?.hooks else {
            hookEntries = []
            return
        }

        var entries: [HookHealthEntry] = []

        for (hookType, groups) in hooks.sorted(by: { $0.key < $1.key }) {
            for group in groups {
                let hookList = group.hooks ?? []
                let commandHooks = hookList.filter { $0.type == "command" }
                let promptHooks = hookList.filter { $0.type == "prompt" }

                var scriptPaths: [String] = []
                var statuses: [String: HookHealthEntry.ScriptStatus] = [:]

                for hook in commandHooks {
                    guard let cmd = hook.command else { continue }
                    if let path = extractScriptPath(from: cmd) {
                        scriptPaths.append(path)
                        statuses[path] = checkScriptStatus(path: path)
                    } else {
                        // Inline command — no resolvable file path
                        let key = String(cmd.prefix(50))
                        statuses[key] = .inline
                    }
                }

                entries.append(HookHealthEntry(
                    hookType: hookType,
                    totalHooks: hookList.count,
                    commandHooks: commandHooks.count,
                    promptHooks: promptHooks.count,
                    matcher: group.matcher,
                    scriptPaths: scriptPaths,
                    scriptStatuses: statuses
                ))
            }
        }

        hookEntries = entries
    }

    // MARK: - Private helpers

    /// Extracts the first absolute script path from a shell command string.
    /// Returns nil for pure inline commands (pipes, one-liners without a script file).
    ///
    /// Only paths that look like runnable scripts are returned — files with non-executable
    /// extensions (e.g. `.aiff`, `.json`, `.png`) are ignored even if their path is absolute,
    /// to avoid false "not executable" warnings for resource files that appear in command args.
    private func extractScriptPath(from command: String) -> String? {
        // Extensions that are definitely not scripts
        let nonScriptExtensions: Set<String> = [
            "aiff", "mp3", "wav", "m4a",
            "json", "plist", "yaml", "yml",
            "png", "jpg", "jpeg", "gif", "svg", "icns", "ico",
            "txt", "md", "log",
            "zip", "tar", "gz",
        ]

        let tokens = command.components(separatedBy: .whitespaces)
        for token in tokens {
            guard !token.isEmpty else { continue }
            let expanded = NSString(string: token).expandingTildeInPath
            // Must start with "/" (absolute path) and not contain shell operators
            guard expanded.hasPrefix("/") else { continue }
            guard !expanded.contains("|"),
                  !expanded.contains(";"),
                  !expanded.contains("&"),
                  !expanded.contains(">"),
                  !expanded.contains("<") else { continue }

            let url = URL(fileURLWithPath: expanded)
            let ext = url.pathExtension.lowercased()

            // Skip known non-script file types
            if !ext.isEmpty && nonScriptExtensions.contains(ext) { continue }

            // Treat as a script path if it exists on disk or has a script-like extension
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
            // No extension or a dot-extension that isn't blacklisted → potential script
            if !ext.isEmpty {
                return expanded
            }
        }
        return nil
    }

    private func checkScriptStatus(path: String) -> HookHealthEntry.ScriptStatus {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return .missing
        }
        guard fm.isExecutableFile(atPath: path) else {
            return .notExecutable
        }
        return .ok
    }
}
