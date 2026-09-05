import SwiftUI
import AppKit

struct DashboardActiveSessionsSection: View {
    let sessionService: SessionService

    var body: some View {
                // Active sessions
                if !sessionService.activeSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Active Sessions")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            // Longest session badge
                            if let longest = sessionService.activeSessions.max(by: { $0.duration < $1.duration }) {
                                Text("longest: \(longest.duration.formattedDuration)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()
                            Text("\(sessionService.activeSessions.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 12)

                        ForEach(sessionService.activeSessions) { session in
                            HStack(spacing: 6) {
                                SessionRow(
                                    projectName: session.projectName,
                                    detail: session.cwd,
                                    duration: session.duration.formattedDuration,
                                    isActive: true
                                )
                                if let ctx = sessionService.contextEstimates[session.sessionId],
                                   ctx > 0 {
                                    ContextGauge(percentage: ctx, compact: true)
                                        .help("Estimated context window usage (approximation based on JSONL file size — actual usage may differ)")
                                }
                            }
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                ProcessHelper.focusTerminal(forChildPID: session.pid)
                            }
                            .onHover { hovering in
                                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
    }

}

