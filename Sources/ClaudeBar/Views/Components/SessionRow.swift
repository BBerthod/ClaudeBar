import SwiftUI

struct SessionRow: View {
    let projectName: String
    let detail: String
    let duration: String
    var isActive: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Active indicator
            if isActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                    .shadow(color: .green.opacity(0.5), radius: 3)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }

            // Project info
            VStack(alignment: .leading, spacing: 2) {
                Text(projectName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Duration
            Text(duration)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    VStack(spacing: 8) {
        SessionRow(
            projectName: "my-laravel-app",
            detail: "/Users/username/Dev/my-laravel-app",
            duration: "2h 15m",
            isActive: true
        )
        SessionRow(
            projectName: "ClaudeBar",
            detail: "/Users/username/Dev/ClaudeBar",
            duration: "45m",
            isActive: false
        )
    }
    .padding()
    .frame(width: 360)
}
