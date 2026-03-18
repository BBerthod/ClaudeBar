import Foundation

struct HookHealthEntry: Identifiable, Sendable {
    let hookType: String           // "SessionStart", "Stop", "PreToolUse", etc.
    let totalHooks: Int            // number of hook entries
    let commandHooks: Int          // hooks with type == "command"
    let promptHooks: Int           // hooks with type == "prompt"
    let matcher: String?           // optional matcher pattern
    let scriptPaths: [String]      // extracted command paths
    let scriptStatuses: [String: ScriptStatus]  // path -> status

    var id: String { hookType + (matcher ?? "") }

    enum ScriptStatus: String, Sendable {
        case ok = "OK"
        case missing = "Missing"
        case notExecutable = "Not executable"
        case inline = "Inline"  // one-liner shell command, not a script file
    }
}
