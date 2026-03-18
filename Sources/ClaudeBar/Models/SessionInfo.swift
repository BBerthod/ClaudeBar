import Foundation

// MARK: - ActiveSession

/// Decoded from `~/.claude/sessions/{pid}.json`.
/// Represents a currently running Claude Code process.
struct ActiveSession: Codable, Sendable, Identifiable {
    let pid: Int
    let sessionId: String
    let cwd: String
    /// Unix timestamp in milliseconds.
    let startedAt: Int

    var id: String { sessionId }

    /// The date the session started.
    var startDate: Date {
        Date(timeIntervalSince1970: Double(startedAt) / 1_000.0)
    }

    /// How long the session has been running (seconds).
    var duration: TimeInterval {
        Date().timeIntervalSince(startDate)
    }

    /// The last path component of `cwd`, used as a human-readable project name.
    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}

// MARK: - SessionIndexEntry

/// One entry inside a `sessions-index.json` file found under
/// `~/.claude/projects/*/sessions-index.json`.
struct SessionIndexEntry: Codable, Sendable, Identifiable {
    let sessionId: String
    let fullPath: String
    /// File modification time as Unix timestamp in milliseconds.
    let fileMtime: Int?
    let firstPrompt: String?
    let summary: String?
    /// Number of messages in the session; optional for forward compatibility.
    let messageCount: Int?
    /// ISO-8601 creation timestamp.
    let created: String?
    /// ISO-8601 last-modified timestamp.
    let modified: String?
    let gitBranch: String?
    let projectPath: String
    let isSidechain: Bool?

    var id: String { sessionId }

    /// The last path component of `projectPath`.
    var projectName: String {
        URL(fileURLWithPath: projectPath).lastPathComponent
    }
}

// MARK: - SessionIndex

/// Root object decoded from a `sessions-index.json` file.
struct SessionIndex: Codable, Sendable {
    let version: Int
    let entries: [SessionIndexEntry]
    let originalPath: String
}
