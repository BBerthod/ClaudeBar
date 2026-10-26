import Foundation
import os

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
            Log.settings.error("Failed to load settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Write

    /// Writes `settings` to disk without dropping what ClaudeBar does not model: the file is
    /// re-read as a generic JSON object and only the entries that differ from the settings
    /// loaded earlier are patched into it. Unknown keys (and unknown nested fields) survive.
    func saveSettings(_ settings: ClaudeSettings) throws {
        let url = URL(fileURLWithPath: settingsPath)
        var raw: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsPath) {
            let existing = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            raw = object
        }
        let old = try Self.jsonObject(self.settings ?? ClaudeSettings())
        let new = try Self.jsonObject(settings)
        let merged = Self.merge(raw, old: old, new: new)
        let data = try JSONSerialization.data(
            withJSONObject: merged,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
        self.settings = settings
    }

    private static func jsonObject(_ settings: ClaudeSettings) throws -> [String: Any] {
        let data = try JSONEncoder().encode(settings)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    /// Applies to `raw` the difference between `old` and `new`, recursing into nested objects.
    private static func merge(_ raw: [String: Any], old: [String: Any], new: [String: Any]) -> [String: Any] {
        var result = raw
        for key in Set(old.keys).union(new.keys) {
            guard let newValue = new[key] else {
                result.removeValue(forKey: key)
                continue
            }
            if let oldValue = old[key], (oldValue as AnyObject).isEqual(newValue) { continue }
            if let newDict = newValue as? [String: Any], let rawDict = result[key] as? [String: Any] {
                result[key] = merge(rawDict, old: old[key] as? [String: Any] ?? [:], new: newDict)
            } else {
                result[key] = newValue
            }
        }
        return result
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
    func togglePlugin(name: String, enabled: Bool) {
        var current = settings ?? ClaudeSettings()
        guard var plugins = current.plugins else { return }
        guard let idx = plugins.firstIndex(where: { $0.name == name }) else { return }
        plugins[idx].enabled = enabled
        current.plugins = plugins
        do {
            try saveSettings(current)
        } catch {
            lastError = error.localizedDescription
            Log.settings.error("Failed to save settings: \(error.localizedDescription)")
        }
    }

    /// Set the effort level (e.g. "low", "medium", "high").
    func setEffortLevel(_ level: String) {
        var current = settings ?? ClaudeSettings()
        current.effortLevel = level
        do {
            try saveSettings(current)
        } catch {
            lastError = error.localizedDescription
            Log.settings.error("Failed to save settings: \(error.localizedDescription)")
        }
    }

    /// Enable or disable the "always thinking" model behaviour.
    func setThinkingEnabled(_ enabled: Bool) {
        var current = settings ?? ClaudeSettings()
        current.alwaysThinkingEnabled = enabled
        do {
            try saveSettings(current)
        } catch {
            lastError = error.localizedDescription
            Log.settings.error("Failed to save settings: \(error.localizedDescription)")
        }
    }

    // MARK: - File Watching

    private func startWatching() {
        fileWatcher.watch(path: settingsPath) { [weak self] in
            self?.loadSettings()
        }
    }
}
