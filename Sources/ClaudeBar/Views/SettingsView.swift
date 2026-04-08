import SwiftUI
import Darwin

struct SettingsView: View {
    var settingsService: SettingsService
    var hookHealthService: HookHealthService
    var notificationService: NotificationService
    var launchAtLoginService: LaunchAtLoginService
    var sessionService: SessionService
    var statsService: StatsService
    var mcpHealthService: McpHealthService

    @State private var expandedPermissions = false
    @State private var expandedHooks = false
    @State private var expandedHookHealth = false
    @State private var staleCleaned = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = settingsService.lastError {
                    errorBanner(error)
                }

                quickActionsSection

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

                mcpSection

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

            Divider()

            // Stats-cache freshness
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Stats Cache", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                    Spacer()
                    if let lastDate = statsService.stats?.lastComputedDate {
                        let daysAgo = daysSince(lastDate)
                        Text(daysAgo == 0 ? "fresh" : "\(daysAgo)d old")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(daysAgo > 1 ? .orange : .green)
                    } else {
                        Text("unavailable")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Text("Claude Code recalculates this automatically between sessions")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(8)

            Divider()

            // Stale session cleanup
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Session Files", systemImage: "trash")
                        .font(.subheadline)
                    Spacer()
                    Button("Clean Stale") {
                        staleCleaned = cleanStaleSessions()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if staleCleaned > 0 {
                    Text("Removed \(staleCleaned) stale session file\(staleCleaned == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .padding(8)
        } label: {
            sectionLabel("App")
        }
        .padding(.horizontal, 12)
    }

    private func daysSince(_ dateStr: String) -> Int {
        guard let date = DateFormatter.isoDate.date(from: dateStr) else { return 99 }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }

    private func cleanStaleSessions() -> Int {
        let dir = NSString(string: "~/.claude/sessions").expandingTildeInPath
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return 0 }

        var removed = 0
        for file in files where file.hasSuffix(".json") {
            let path = dir + "/" + file
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let session = try? JSONDecoder().decode(ActiveSession.self, from: data) else { continue }

            // Check if process is dead.
            // kill(pid, 0) returns -1 with errno == EPERM when the process exists but
            // is owned by a different user — that is NOT a dead process.
            // Only ESRCH means the process truly doesn't exist.
            let rc = kill(Int32(session.pid), 0)
            if rc != 0 && errno == ESRCH {
                try? fm.removeItem(atPath: path)
                removed += 1
            }
        }
        return removed
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

                // Sound alerts
                Toggle(isOn: Binding(
                    get: { notificationService.soundEnabled },
                    set: { notificationService.setSoundEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sound Alerts")
                            .font(.subheadline)
                        Text("Play a sound when usage thresholds are crossed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

    // MARK: - MCP Servers

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
            sectionLabel("MCP Servers (\(mcpHealthService.servers.count))")
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // File shortcuts
                HStack(spacing: 8) {
                    quickActionButton(
                        title: "settings.json",
                        icon: "doc.text",
                        action: { openInEditor("~/.claude/settings.json") }
                    )
                    quickActionButton(
                        title: ".claude.json",
                        icon: "gearshape.2",
                        action: { openInEditor("~/.claude.json") }
                    )
                    quickActionButton(
                        title: "~/.claude",
                        icon: "folder",
                        action: {
                            let path = NSString(string: "~/.claude").expandingTildeInPath
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                    )
                }

                Divider()

                // Claude launch shortcuts
                Text("Launch Claude Code")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    claudeLaunchButton(
                        title: "claude",
                        subtitle: "interactive",
                        icon: "terminal",
                        flags: []
                    )
                    claudeLaunchButton(
                        title: "claude --continue",
                        subtitle: "resume last",
                        icon: "arrow.uturn.backward",
                        flags: ["--continue"]
                    )
                    claudeLaunchButton(
                        title: "claude --chrome",
                        subtitle: "browser mode",
                        icon: "globe",
                        flags: ["--chrome"]
                    )
                    claudeLaunchButton(
                        title: "claude YOLO",
                        subtitle: "skip permissions",
                        icon: "bolt.shield",
                        flags: ["--dangerously-skip-permissions"]
                    )
                    claudeLaunchButton(
                        title: "claude plan",
                        subtitle: "plan mode",
                        icon: "list.clipboard",
                        flags: ["--permission-mode", "plan"]
                    )
                    claudeLaunchButton(
                        title: "claude auto",
                        subtitle: "auto mode",
                        icon: "play.circle",
                        flags: ["--permission-mode", "auto"]
                    )
                }
            }
            .padding(8)
        } label: {
            sectionLabel("Quick Actions")
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func quickActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private func claudeLaunchButton(title: String, subtitle: String, icon: String, flags: [String]) -> some View {
        Button {
            launchClaudeInTerminal(flags: flags)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func launchClaudeInTerminal(flags: [String]) {
        var cmdParts = ["claude"]
        cmdParts.append(contentsOf: flags)
        let command = cmdParts.joined(separator: " ")

        // Detect which terminal is available
        let iTermRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").isEmpty

        // Use the ARGV pattern to pass the command as an argument — no string interpolation
        // into the AppleScript source, preventing injection via crafted flag values.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")

        if iTermRunning {
            process.arguments = [
                "-e", "on run argv",
                "-e", "tell application \"iTerm2\"",
                "-e", "    activate",
                "-e", "    tell current window",
                "-e", "        create tab with default profile",
                "-e", "        tell current session",
                "-e", "            write text (item 1 of argv)",
                "-e", "        end tell",
                "-e", "    end tell",
                "-e", "end tell",
                "-e", "end run",
                "--", command
            ]
        } else {
            process.arguments = [
                "-e", "on run argv",
                "-e", "tell application \"Terminal\"",
                "-e", "    activate",
                "-e", "    do script (item 1 of argv)",
                "-e", "end tell",
                "-e", "end run",
                "--", command
            ]
        }

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func openInEditor(_ path: String) {
        let expanded = NSString(string: path).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
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
        guard value.count > 4 else { return String(repeating: "•", count: value.count) }
        return String(repeating: "•", count: value.count - 4) + value.suffix(4)
    }
}

#Preview {
    SettingsView(
        settingsService: SettingsService(),
        hookHealthService: HookHealthService(),
        notificationService: NotificationService(),
        launchAtLoginService: LaunchAtLoginService(),
        sessionService: SessionService(),
        statsService: StatsService(),
        mcpHealthService: McpHealthService()
    )
    .frame(width: 420, height: 480)
}
