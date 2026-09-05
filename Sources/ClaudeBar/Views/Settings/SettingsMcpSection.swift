import SwiftUI

struct SettingsMcpSection: View {
    let mcpHealthService: McpHealthService

    var body: some View {
        mcpSection
    }
    @ViewBuilder
    private var mcpSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("MCP Servers", systemImage: "server.rack")
                        .font(.subheadline)
                    Spacer()
                    Button {
                        mcpHealthService.checkAll()
                    } label: {
                        if mcpHealthService.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Check All", systemImage: "stethoscope")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(mcpHealthService.isChecking)
                }

                if mcpHealthService.servers.isEmpty {
                    Text("No MCP servers configured in ~/.claude.json")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(mcpHealthService.servers) { server in
                        HStack(spacing: 8) {
                            // Status dot
                            Circle()
                                .fill(server.status.color)
                                .frame(width: 7, height: 7)

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(server.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(server.type)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                Text(server.endpoint)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(server.status.label)
                                .font(.caption2)
                                .foregroundStyle(server.status.color)
                        }
                    }
                }
            }
            .padding(8)
        } label: {
            SettingsSectionLabel("MCP Servers (\(mcpHealthService.servers.count))")
        }
        .padding(.horizontal, 12)
    }

}

