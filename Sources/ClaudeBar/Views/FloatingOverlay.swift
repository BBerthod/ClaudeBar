import SwiftUI

struct FloatingOverlayContent: View {
    @Environment(SessionService.self) private var sessionService
    @State private var hoveredSession: String? // sessionId

    var body: some View {
        VStack(spacing: 4) {
            // Header with drag handle
            HStack {
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Sessions")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(sessionService.activeSessions.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            if sessionService.activeSessions.isEmpty {
                Text("No active sessions")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(sessionService.activeSessions) { session in
                    FloatingSessionPill(
                        session: session,
                        contextPercent: sessionService.contextEstimates[session.sessionId],
                        isHovered: hoveredSession == session.sessionId
                    )
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredSession = hovering ? session.sessionId : nil
                        }
                    }
                    .onTapGesture {
                        ProcessHelper.focusTerminal(forChildPID: session.pid)
                    }
                }
            }
        }
        .padding(.bottom, 6)
        .frame(width: 180)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

struct FloatingSessionPill: View {
    let session: ActiveSession
    let contextPercent: Double?
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Status dot (green = active)
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)

            // Project name
            Text(session.projectName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer()

            // Context gauge (tiny)
            if let ctx = contextPercent, ctx > 0.05 {
                Text("\(Int(ctx * 100))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(contextColor(ctx))
            }

            // Duration
            Text(session.duration.formattedDuration)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 4)
        .scaleEffect(isHovered ? 1.02 : 1.0)
    }

    private func contextColor(_ pct: Double) -> Color {
        switch pct {
        case ..<0.4: return .green
        case 0.4..<0.6: return .yellow
        case 0.6..<0.8: return .orange
        default: return .red
        }
    }
}
