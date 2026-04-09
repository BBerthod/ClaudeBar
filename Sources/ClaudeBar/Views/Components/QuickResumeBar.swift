import SwiftUI
import AppKit

/// A search bar with autocomplete for quick session resume.
/// Filters recent sessions by search text (summary, projectName, gitBranch).
/// Clicking a result copies `claude --resume {sessionId}` to the clipboard.
struct QuickResumeBar: View {
    let recentSessions: [SessionIndexEntry]

    @State private var searchText = ""
    @State private var showCopied = false
    @State private var copiedSessionId: String?

    private var filteredSessions: [SessionIndexEntry] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        return recentSessions.filter { entry in
            entry.projectName.lowercased().contains(query)
            || (entry.summary?.lowercased().contains(query) ?? false)
            || (entry.gitBranch?.lowercased().contains(query) ?? false)
        }
        .prefix(6)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("Quick resume… (project, branch, summary)", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            // Dropdown results
            if !filteredSessions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredSessions) { entry in
                        resultRow(entry)
                        if entry.id != filteredSessions.last?.id {
                            Divider()
                                .padding(.leading, 10)
                        }
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ entry: SessionIndexEntry) -> some View {
        let isCopied = copiedSessionId == entry.sessionId && showCopied

        Button {
            copyResumeCommand(for: entry)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.projectName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if let summary = entry.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let branch = entry.gitBranch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if isCopied {
                        Label("Copied!", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Label("Resume", systemImage: "doc.on.clipboard")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func copyResumeCommand(for entry: SessionIndexEntry) {
        let command = "claude --resume \(entry.sessionId)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)

        copiedSessionId = entry.sessionId
        showCopied = true

        // Reset after 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedSessionId == entry.sessionId {
                showCopied = false
                copiedSessionId = nil
            }
        }
    }
}

#Preview {
    let sessions: [SessionIndexEntry] = [
        SessionIndexEntry(
            sessionId: "abc123",
            fullPath: "/path/to/file.jsonl",
            fileMtime: nil,
            firstPrompt: nil,
            summary: "Add authentication flow to dashboard",
            messageCount: 42,
            created: nil,
            modified: "2026-03-17T10:00:00Z",
            gitBranch: "feature/auth",
            projectPath: "/Users/username/Dev/my-laravel-app",
            isSidechain: nil
        ),
        SessionIndexEntry(
            sessionId: "def456",
            fullPath: "/path/to/file2.jsonl",
            fileMtime: nil,
            firstPrompt: nil,
            summary: "Fix payment gateway timeout issue",
            messageCount: 18,
            created: nil,
            modified: "2026-03-16T15:30:00Z",
            gitBranch: "hotfix/payment",
            projectPath: "/Users/username/Dev/shop-backend",
            isSidechain: nil
        ),
    ]

    VStack(spacing: 16) {
        QuickResumeBar(recentSessions: sessions)
    }
    .padding()
    .frame(width: 420)
}
