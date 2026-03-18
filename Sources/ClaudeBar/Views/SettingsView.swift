import SwiftUI

struct SettingsView: View {
    var settingsService: SettingsService

    @State private var expandedPermissions = false
    @State private var expandedHooks = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = settingsService.lastError {
                    errorBanner(error)
                }

                if let settings = settingsService.settings {
                    modelBehaviorSection(settings)
                    pluginsSection(settings)
                    envVarsSection(settings)
                    permissionsSection(settings)
                    hooksSection(settings)
                } else {
                    loadingState
                }

                Spacer(minLength: 12)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Model & Behavior

    @ViewBuilder
    private func modelBehaviorSection(_ settings: ClaudeSettings) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Always thinking toggle
                if let thinkingEnabled = settings.alwaysThinkingEnabled {
                    Toggle(isOn: Binding(
                        get: { thinkingEnabled },
                        set: { newVal in
                            try? settingsService.setThinkingEnabled(newVal)
                        }
                    )) {
                        Label("Always thinking enabled", systemImage: "brain")
                            .font(.subheadline)
                    }
                }

                Divider()

                // Effort level
                if let effort = settings.effortLevel {
                    HStack {
                        Label("Effort level", systemImage: "speedometer")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { effort },
                            set: { newVal in try? settingsService.setEffortLevel(newVal) }
                        )) {
                            Text("Low").tag("low")
                            Text("Medium").tag("medium")
                            Text("High").tag("high")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                }

                // Enable all project MCP
                if let mcpEnabled = settings.enableAllProjectMcpServers {
                    Divider()
                    Toggle(isOn: Binding(
                        get: { mcpEnabled },
                        set: { _ in } // read-only for now; could hook into saveSettings
                    )) {
                        Label("Enable all project MCP servers", systemImage: "server.rack")
                            .font(.subheadline)
                    }
                }
            }
            .padding(8)
        } label: {
            sectionLabel("Model & Behavior")
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Plugins

    @ViewBuilder
    private func pluginsSection(_ settings: ClaudeSettings) -> some View {
        if let plugins = settings.plugins, !plugins.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plugins.indices, id: \.self) { idx in
                        let plugin = plugins[idx]
                        HStack {
                            Image(systemName: "puzzlepiece.extension")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(plugin.name)
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { plugin.enabled },
                                set: { newVal in
                                    try? settingsService.togglePlugin(name: plugin.name, enabled: newVal)
                                }
                            ))
                            .labelsHidden()
                        }
                        if idx < plugins.count - 1 { Divider() }
                    }
                }
                .padding(8)
            } label: {
                sectionLabel("Plugins (\(plugins.count))")
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Environment Variables

    @ViewBuilder
    private func envVarsSection(_ settings: ClaudeSettings) -> some View {
        if let envVars = settings.environmentVariables, !envVars.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(envVars.keys.sorted().enumerated()), id: \.offset) { idx, key in
                        HStack(alignment: .top) {
                            Text(key)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(maskedValue(envVars[key] ?? ""))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if idx < envVars.count - 1 { Divider() }
                    }
                }
                .padding(8)
            } label: {
                sectionLabel("Environment Variables (\(envVars.count))")
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Permissions

    @ViewBuilder
    private func permissionsSection(_ settings: ClaudeSettings) -> some View {
        if let permissions = settings.permissions {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    permissionList("Allow", items: permissions.allow ?? [], color: .green)
                    if !(permissions.allow ?? []).isEmpty && !(permissions.deny ?? []).isEmpty {
                        Divider()
                    }
                    permissionList("Deny", items: permissions.deny ?? [], color: .red)
                    if !(permissions.deny ?? []).isEmpty && !(permissions.ask ?? []).isEmpty {
                        Divider()
                    }
                    permissionList("Ask", items: permissions.ask ?? [], color: .orange)
                }
                .padding(8)
            } label: {
                sectionLabel("Permissions")
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private func permissionList(_ label: String, items: [String], color: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(color)
                            .frame(width: 4, height: 4)
                        Text(item)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Hooks

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
                sectionLabel("Hooks")
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.medium)
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    private var loadingState: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading settings…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 40)
            Spacer()
        }
    }

    private func maskedValue(_ value: String) -> String {
        guard value.count > 4 else { return "••••" }
        // Show last 4 chars of secrets, full value for non-secret-looking ones
        let lower = value.lowercased()
        let looksSecret = lower.contains("key") || lower.contains("token") || lower.contains("secret") || value.count > 20
        if looksSecret {
            return "••••" + String(value.suffix(4))
        }
        return value
    }
}

#Preview {
    SettingsView(settingsService: SettingsService())
        .frame(width: 420, height: 480)
}
