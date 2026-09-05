import SwiftUI

struct SettingsHooksSection: View {
    let settings: ClaudeSettings
    let hookHealthService: HookHealthService

    @State private var expandedHookHealth = false

    var body: some View {
        Group {
            hooksSection(settings)
            hookHealthSection
        }
    }
    @ViewBuilder
    private func hooksSection(_ settings: ClaudeSettings) -> some View {
        if let hooks = settings.hooks, !hooks.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(hooks.keys.sorted().enumerated()), id: \.offset) { idx, hookType in
                        let hookList = hooks[hookType] ?? []
                        HStack {
                            Image(systemName: "arrow.uturn.right")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(hookType)
                                .font(.subheadline)
                            Spacer()
                            Text("\(hookList.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        if idx < hooks.count - 1 { Divider() }
                    }
                }
                .padding(8)
            } label: {
                SettingsSectionLabel("Hooks")
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Hook Health

    @ViewBuilder
    private var hookHealthSection: some View {
        if hookHealthService.totalHookTypes > 0 {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    // Summary row
                    HStack {
                        Label(
                            "\(hookHealthService.totalHookTypes) types, \(hookHealthService.totalHooks) hooks",
                            systemImage: "shield.checkered"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                        if hookHealthService.issueCount > 0 {
                            Label("\(hookHealthService.issueCount) issue\(hookHealthService.issueCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Label("All OK", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    if expandedHookHealth {
                        Divider()

                        // Stats-cache status
                        HStack {
                            Label("Stats Cache", systemImage: "doc.text")
                                .font(.caption)
                            Spacer()
                            Text(hookHealthService.statsCacheStatus.rawValue)
                                .font(.caption)
                                .foregroundStyle(cacheStatusColor(hookHealthService.statsCacheStatus))
                            Circle()
                                .fill(cacheStatusColor(hookHealthService.statsCacheStatus))
                                .frame(width: 6, height: 6)
                        }

                        // OAuth credential status
                        HStack {
                            Label("OAuth Credentials", systemImage: "key")
                                .font(.caption)
                            Spacer()
                            Text(hookHealthService.hasOAuthCredentials ? "Found" : "Not found")
                                .font(.caption)
                                .foregroundStyle(hookHealthService.hasOAuthCredentials ? .green : .red)
                            Circle()
                                .fill(hookHealthService.hasOAuthCredentials ? .green : .red)
                                .frame(width: 6, height: 6)
                        }

                        Divider()

                        // Per-entry list
                        ForEach(hookHealthService.hookEntries) { entry in
                            hookEntryRow(entry)
                        }
                    }
                }
                .padding(8)
            } label: {
                HStack {
                    SettingsSectionLabel("Hook Health")
                    Spacer()
                    Button {
                        withAnimation { expandedHookHealth.toggle() }
                    } label: {
                        Image(systemName: expandedHookHealth ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private func hookEntryRow(_ entry: HookHealthEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.hookType)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let matcher = entry.matcher {
                    Text(matcher)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
                Spacer()
                Text("\(entry.totalHooks) hook\(entry.totalHooks == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Script statuses
            if !entry.scriptStatuses.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(entry.scriptStatuses.keys.sorted()), id: \.self) { path in
                        if let status = entry.scriptStatuses[path] {
                            HStack(spacing: 5) {
                                scriptStatusIcon(status)
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(status.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(scriptStatusColor(status))
                            }
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder
    private func scriptStatusIcon(_ status: HookHealthEntry.ScriptStatus) -> some View {
        switch status {
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .missing:
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .notExecutable:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
        case .inline:
            Image(systemName: "minus.circle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func scriptStatusColor(_ status: HookHealthEntry.ScriptStatus) -> Color {
        switch status {
        case .ok:            return .green
        case .missing:       return .red
        case .notExecutable: return .yellow
        case .inline:        return .secondary
        }
    }

    private func cacheStatusColor(_ status: HookHealthService.CacheStatus) -> Color {
        switch status {
        case .fresh:   return .green
        case .stale:   return .orange
        case .missing: return .red
        case .unknown: return .secondary
        }
    }

}

