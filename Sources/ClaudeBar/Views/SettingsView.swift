import SwiftUI

struct SettingsView: View {
    var settingsService: SettingsService
    var hookHealthService: HookHealthService
    var notificationService: NotificationService
    var launchAtLoginService: LaunchAtLoginService

    @State private var expandedPermissions = false
    @State private var expandedHooks = false
    @State private var expandedHookHealth = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = settingsService.lastError {
                    errorBanner(error)
                }

                appSection()

                if let settings = settingsService.settings {
                    notificationsSection()
                    modelBehaviorSection(settings)
                    pluginsSection(settings)
                    envVarsSection(settings)
                    permissionsSection(settings)
                    hooksSection(settings)
                    hookHealthSection
                } else {
                    loadingState
                }

                Spacer(minLength: 12)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - App

    @ViewBuilder
    private func appSection() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if launchAtLoginService.isAvailable {
                    Toggle(isOn: Binding(
                        get: { launchAtLoginService.isEnabled },
                        set: { launchAtLoginService.setEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at Login")
                                .font(.subheadline)
                            Text("Start ClaudeBar automatically at login")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Toggle(isOn: .constant(false)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at Login")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Requires .app bundle (not available in swift run mode)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(true)
                }
            }
            .padding(8)
        } label: {
            sectionLabel("App")
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Notifications

    @ViewBuilder
    private func notificationsSection() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Authorization status
                HStack {
                    Label(
                        "Notifications",
                        systemImage: notificationService.isAuthorized ? "bell.badge" : "bell.slash"
                    )
                    .font(.subheadline)
                    Spacer()
                    Text(notificationService.isAuthorized ? "Authorized" : "Not authorized")
                        .font(.caption)
                        .foregroundStyle(notificationService.isAuthorized ? .green : .red)
                }

                Divider()

                // Daily digest time
                HStack {
                    Label("Daily digest", systemImage: "clock")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { notificationService.dailyDigestTime },
                        set: { notificationService.setDailyDigestTime($0) }
                    )) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formatHour(hour)).tag(hour)
                        }
                    }
                    .frame(width: 100)
                }

                Divider()

                // Cost threshold
                HStack {
                    Label("Cost alert", systemImage: "dollarsign.circle")
                        .font(.subheadline)
                    Spacer()
                    Text("$")
                        .font(.subheadline)
                    TextField("", value: Binding(
                        get: { notificationService.costThreshold },
                        set: { notificationService.setCostThreshold($0) }
                    ), format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                }
            }
            .padding(8)
        } label: {
            sectionLabel("Notifications")
        }
        .padding(.horizontal, 12)
    }

    private func formatHour(_ hour: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return f.string(from: date)
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
                        set: { _ in } // read-only for now
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

                    Divider()

                    // Per-entry list
                    ForEach(hookHealthService.hookEntries) { entry in
                        hookEntryRow(entry)
                    }
                }
                .padding(8)
            } label: {
                HStack {
                    sectionLabel("Hook Health")
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
        let lower = value.lowercased()
        let looksSecret = lower.contains("key") || lower.contains("token") || lower.contains("secret") || value.count > 20
        if looksSecret {
            return "••••" + String(value.suffix(4))
        }
        return value
    }
}

#Preview {
    SettingsView(
        settingsService: SettingsService(),
        hookHealthService: HookHealthService(),
        notificationService: NotificationService(),
        launchAtLoginService: LaunchAtLoginService()
    )
    .frame(width: 420, height: 480)
}
