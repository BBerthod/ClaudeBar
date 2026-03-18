import Foundation

// MARK: - Permissions

/// Tool-use permission lists from `settings.json`.
struct Permissions: Codable, Sendable {
    var allow: [String]?
    var deny: [String]?
    var ask: [String]?
}

// MARK: - HookEntry

/// An individual hook command or prompt.
struct HookEntry: Codable, Sendable {
    /// Hook type, e.g. "command" or "prompt".
    var type: String
    /// Shell command to execute (used when type == "command").
    var command: String?
    /// Prompt text (used when type == "prompt").
    var prompt: String?
    /// Timeout in seconds.
    var timeout: Int?
}

// MARK: - HookGroup

/// A group of hooks that share an optional glob matcher.
struct HookGroup: Codable, Sendable {
    /// Optional glob pattern for path-scoped hooks.
    var matcher: String?
    var hooks: [HookEntry]?
}

// MARK: - StatusLine

/// Configuration for the terminal status-line command.
struct StatusLine: Codable, Sendable {
    /// Type of status line, e.g. "command".
    var type: String?
    /// Shell command whose output is shown in the status line.
    var command: String?
}

// MARK: - PluginEntry

/// A named plugin with an on/off flag, as displayed in the settings UI.
///
/// In `settings.json` plugins are stored as a flat dict
/// (`enabledPlugins: { "superpowers": true, … }`).
/// This struct is the view-friendly representation that
/// `SettingsService` exposes after unpacking that dict.
struct PluginEntry: Codable, Sendable, Identifiable {
    var name: String
    var enabled: Bool

    var id: String { name }
}

// MARK: - ClaudeSettings

/// Root object decoded from `~/.claude/settings.json`.
///
/// Only the fields ClaudeBar cares about are modelled here;
/// unknown keys are silently ignored by the Codable decoder.
struct ClaudeSettings: Codable, Sendable {

    // MARK: Stored properties (all mutable for in-place patching)

    /// Extra environment variables injected into every Claude session.
    /// Stored in JSON as `env`, exposed as `environmentVariables` for readability.
    var env: [String: String]?

    var permissions: Permissions?

    /// Lifecycle hooks keyed by event name
    /// (e.g. "PreCompact", "PostToolCall", "TeammateIdle").
    var hooks: [String: [HookGroup]]?

    var enableAllProjectMcpServers: Bool?

    var statusLine: StatusLine?

    /// Plugin enable/disable flags keyed by plugin name.
    var enabledPlugins: [String: Bool]?

    var alwaysThinkingEnabled: Bool?
    var effortLevel: String?
    var plansDirectory: String?
    var teammateMode: String?

    // MARK: Memberwise init

    init(
        env: [String: String]? = nil,
        permissions: Permissions? = nil,
        hooks: [String: [HookGroup]]? = nil,
        enableAllProjectMcpServers: Bool? = nil,
        statusLine: StatusLine? = nil,
        enabledPlugins: [String: Bool]? = nil,
        alwaysThinkingEnabled: Bool? = nil,
        effortLevel: String? = nil,
        plansDirectory: String? = nil,
        teammateMode: String? = nil
    ) {
        self.env = env
        self.permissions = permissions
        self.hooks = hooks
        self.enableAllProjectMcpServers = enableAllProjectMcpServers
        self.statusLine = statusLine
        self.enabledPlugins = enabledPlugins
        self.alwaysThinkingEnabled = alwaysThinkingEnabled
        self.effortLevel = effortLevel
        self.plansDirectory = plansDirectory
        self.teammateMode = teammateMode
    }

    // MARK: Convenience accessors

    /// Alias for `env`, matching the property name used in the settings UI.
    var environmentVariables: [String: String]? {
        get { env }
        set { env = newValue }
    }

    /// Flattened list of plugins derived from `enabledPlugins`.
    /// Returns nil when `enabledPlugins` is nil (not configured).
    var plugins: [PluginEntry]? {
        get {
            guard let enabledPlugins else { return nil }
            return enabledPlugins
                .map { PluginEntry(name: $0.key, enabled: $0.value) }
                .sorted { $0.name < $1.name }
        }
        set {
            guard let newValue else {
                enabledPlugins = nil
                return
            }
            enabledPlugins = Dictionary(
                uniqueKeysWithValues: newValue.map { ($0.name, $0.enabled) }
            )
        }
    }
}
