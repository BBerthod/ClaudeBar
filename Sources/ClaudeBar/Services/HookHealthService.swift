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

    /// Extracts the first absolute file path from a shell command string.
    /// Returns nil for pure inline commands (pipes, one-liners without a script file).
    private func extractScriptPath(from command: String) -> String? {
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

            let lastComponent = URL(fileURLWithPath: expanded).lastPathComponent
            // Treat as a script path if the file exists, or if it has a dot extension (.sh, .py, etc.)
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
            if lastComponent.contains(".") {
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
