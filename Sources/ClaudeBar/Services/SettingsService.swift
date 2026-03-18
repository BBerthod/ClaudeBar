import Foundation

@Observable
@MainActor
final class SettingsService {
    private(set) var settings: ClaudeSettings?
    private(set) var lastError: String?
    private var fileWatcher = FileWatcher()

    private let settingsPath: String

    init(claudeDir: String = "~/.claude") {
        self.settingsPath = NSString(string: claudeDir).expandingTildeInPath + "/settings.json"
        loadSettings()
        startWatching()
    }

    // MARK: - Read

    private func loadSettings() {
        let url = URL(fileURLWithPath: settingsPath)
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            settings = try decoder.decode(ClaudeSettings.self, from: data)
            lastError = nil
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // File doesn't exist — not an error
            settings = nil
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Write

    func saveSettings(_ settings: ClaudeSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        try data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
        self.settings = settings
    }

    // MARK: - Convenience Mutators

    /// Set or update a single environment variable, preserving all others.
    func setEnvironmentVariable(key: String, value: String) throws {
        var current = settings ?? ClaudeSettings()
        var envVars = current.environmentVariables ?? [:]
        envVars[key] = value
        current.environmentVariables = envVars
        try saveSettings(current)
    }

    /// Enable or disable a named plugin. No-op if the plugin is not found.
    func togglePlugin(name: String, enabled: Bool) throws {
        var current = settings ?? ClaudeSettings()
        guard var plugins = current.plugins else { return }
        guard let idx = plugins.firstIndex(where: { $0.name == name }) else { return }
        plugins[idx].enabled = enabled
        current.plugins = plugins
        try saveSettings(current)
    }

    /// Set the effort level (e.g. "low", "medium", "high").
    func setEffortLevel(_ level: String) throws {
        var current = settings ?? ClaudeSettings()
        current.effortLevel = level
        try saveSettings(current)
    }

    /// Enable or disable the "always thinking" model behaviour.
    func setThinkingEnabled(_ enabled: Bool) throws {
        var current = settings ?? ClaudeSettings()
        current.alwaysThinkingEnabled = enabled
        try saveSettings(current)
    }

    // MARK: - File Watching

    private func startWatching() {
        fileWatcher.watch(path: settingsPath) { [weak self] in
            self?.loadSettings()
        }
    }
}
