import SwiftUI
import AppKit

struct AnalyticsSessionsPanel: View {
    let sessionService: SessionService

    var body: some View {
        sessionsPanel
    }
    private var totalActiveTime: TimeInterval {
        sessionService.activeSessions.reduce(0) { $0 + $1.duration }
    }

    private var sessionsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sessions")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)

                // Active sessions
                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 7, height: 7)
                                Text("Active Sessions")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }

                            Spacer()

                            if !sessionService.activeSessions.isEmpty {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("\(sessionService.activeSessions.count) running")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                    Text("total: \(totalActiveTime.formattedDuration)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)

                        if sessionService.activeSessions.isEmpty {
                            Text("No active sessions")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 12)
                        } else {
                            Divider().padding(.horizontal, 8)

                            ForEach(sessionService.activeSessions) { session in
                                activeSessionRow(session)

                                if session.id != sessionService.activeSessions.last?.id {
                                    Divider().padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                // Recent sessions
                GroupBox("Recent Sessions (last 20)") {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Summary")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Project")
                                .frame(width: 120, alignment: .trailing)
                            Text("Messages")
                                .frame(width: 75, alignment: .trailing)
                            Text("Branch")
                                .frame(width: 100, alignment: .trailing)
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                        Divider()

                        ForEach(sessionService.recentSessions.prefix(20)) { entry in
                            recentSessionRow(entry)

                            if entry.id != sessionService.recentSessions.prefix(20).last?.id {
                                Divider().padding(.horizontal, 8)
                            }
                        }

                        if sessionService.recentSessions.isEmpty {
                            Text("No recent sessions found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func activeSessionRow(_ session: ActiveSession) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(session.cwd)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(session.duration.formattedDuration)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                Text("PID \(session.pid)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let ctx = sessionService.contextEstimates[session.sessionId], ctx > 0 {
                ContextGauge(percentage: ctx, compact: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            ProcessHelper.focusTerminal(forChildPID: session.pid)
        }
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    @ViewBuilder
    private func recentSessionRow(_ entry: SessionIndexEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                if let summary = entry.summary ?? entry.firstPrompt {
                    Text(summary)
                        .font(.subheadline)
                        .lineLimit(1)
                } else {
                    Text(entry.sessionId.prefix(12) + "…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let modStr = entry.modified {
                    Text(Self.timeAgo(from: modStr))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.projectName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 120, alignment: .trailing)

            Text("\(entry.messageCount ?? 0)")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 75, alignment: .trailing)

            Text(entry.gitBranch ?? "—")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private static func timeAgo(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date: Date
        if let d = formatter.date(from: dateString) {
            date = d
        } else {
            let f2 = ISO8601DateFormatter()
            guard let d = f2.date(from: dateString) else { return String(dateString.prefix(10)) }
            date = d
        }
        let interval = Date().timeIntervalSince(date)
        switch interval {
        case ..<60:        return "just now"
        case ..<3600:      return "\(Int(interval / 60))m ago"
        case ..<86400:     return "\(Int(interval / 3600))h ago"
        default:           return "\(Int(interval / 86400))d ago"
        }
    }

    // MARK: - Savings Panel

}

