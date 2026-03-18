import SwiftUI

struct SessionsView: View {
    var sessionService: SessionService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Active sessions
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Active")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if !sessionService.activeSessions.isEmpty {
                            Text("\(sessionService.activeSessions.count)")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)

                    if sessionService.activeSessions.isEmpty {
                        activeEmptyState
                    } else {
                        ForEach(sessionService.activeSessions) { session in
                            SessionRow(
                                projectName: session.projectName,
                                detail: session.cwd,
                                duration: session.duration.formattedDuration,
                                isActive: true
                            )
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.top, 12)

                Divider()
                    .padding(.horizontal, 12)

                // Recent sessions
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)

                    if sessionService.recentSessions.isEmpty {
                        recentEmptyState
                    } else {
                        ForEach(sessionService.recentSessions.prefix(20)) { entry in
                            recentSessionRow(entry)
                            if entry.id != sessionService.recentSessions.prefix(20).last?.id {
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }

                Spacer(minLength: 12)
            }
        }
    }

    @ViewBuilder
    private func recentSessionRow(_ entry: SessionIndexEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.projectName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let summary = entry.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let modified = entry.modified {
                        Text(timeAgo(from: modified))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let count = entry.messageCount {
                        Text("\(count) msgs")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            HStack(spacing: 6) {
                if let branch = entry.gitBranch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var activeEmptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                Text("No active sessions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 16)
            Spacer()
        }
    }

    private var recentEmptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                Text("No recent sessions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 16)
            Spacer()
        }
    }

    private func timeAgo(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) else {
            // try without fractional seconds
            let f2 = ISO8601DateFormatter()
            guard let d = f2.date(from: dateString) else { return dateString }
            return relativeString(from: d)
        }
        return relativeString(from: date)
    }

    private func relativeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        switch interval {
        case ..<60:        return "just now"
        case ..<3600:      return "\(Int(interval / 60))m ago"
        case ..<86400:     return "\(Int(interval / 3600))h ago"
        default:           return "\(Int(interval / 86400))d ago"
        }
    }
}

#Preview {
    SessionsView(sessionService: SessionService())
        .frame(width: 420, height: 480)
}
