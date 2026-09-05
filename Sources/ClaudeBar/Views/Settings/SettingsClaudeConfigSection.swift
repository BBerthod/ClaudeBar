import SwiftUI

struct SettingsClaudeConfigSection: View {
    let settingsService: SettingsService
    let settings: ClaudeSettings

    var body: some View {
        Group {
            modelBehaviorSection(settings)
            pluginsSection(settings)
            envVarsSection(settings)
            permissionsSection(settings)
        }
    }
    @ViewBuilder
    private func modelBehaviorSection(_ settings: ClaudeSettings) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Always thinking toggle
                if let thinkingEnabled = settings.alwaysThinkingEnabled {
                    Toggle(isOn: Binding(
                        get: { thinkingEnabled },
                        set: { newVal in
                            settingsService.setThinkingEnabled(newVal)
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
                            set: { newVal in settingsService.setEffortLevel(newVal) }
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
                        set: { _ in } // read-only for now
                    )) {
                        Label("Enable all project MCP servers", systemImage: "server.rack")
                            .font(.subheadline)
                    }
                }
            }
            .padding(8)
        } label: {
            SettingsSectionLabel("Model & Behavior")
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
                                    settingsService.togglePlugin(name: plugin.name, enabled: newVal)
                                }
                            ))
                            .labelsHidden()
                        }
                        if idx < plugins.count - 1 { Divider() }
                    }
                }
                .padding(8)
            } label: {
                SettingsSectionLabel("Plugins (\(plugins.count))")
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
                SettingsSectionLabel("Environment Variables (\(envVars.count))")
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
                SettingsSectionLabel("Permissions")
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


    private func maskedValue(_ value: String) -> String {
        guard value.count > 12 else { return String(repeating: "•", count: value.count) }
        return String(repeating: "•", count: value.count - 3) + value.suffix(3)
    }
}

