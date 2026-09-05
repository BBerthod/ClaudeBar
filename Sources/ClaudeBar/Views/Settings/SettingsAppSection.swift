import SwiftUI
import AppKit
import Darwin

struct SettingsAppSection: View {
    let launchAtLoginService: LaunchAtLoginService
    let statsService: StatsService

    @State private var staleCleaned = 0
    @AppStorage("claudebar.showDockIcon") private var showDockIcon: Bool = false
    @AppStorage("claudebar.refreshInterval") private var refreshInterval: Double = 30

    var body: some View {
        appSection()
    }
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

            Toggle(isOn: Binding(
                get: { showDockIcon },
                set: { newVal in
                    showDockIcon = newVal
                    NSApp.setActivationPolicy(newVal ? .regular : .accessory)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show in Dock")
                        .font(.subheadline)
                    Text("Display ClaudeBar icon in the Dock in addition to the menu bar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Refresh interval", systemImage: "clock.arrow.2.circlepath")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: $refreshInterval) {
                        Text("30 sec").tag(30.0)
                        Text("1 min").tag(60.0)
                        Text("5 min").tag(300.0)
                        Text("10 min").tag(600.0)
                        Text("30 min").tag(1800.0)
                        Text("1 hour").tag(3600.0)
                    }
                    .frame(width: 110)
                }
                Text("How often ClaudeBar updates the burn rate and status")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(8)

            Divider()

            HStack(spacing: 8) {
                Button {
                    relaunchApp()
                } label: {
                    Label("Relaunch", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit ClaudeBar", systemImage: "power")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(8)
        } label: {
            SettingsSectionLabel("App")
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


    private func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let process = Process()
        if bundlePath.hasSuffix(".app") {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [bundlePath]
        } else if let execPath = Bundle.main.executablePath {
            process.executableURL = URL(fileURLWithPath: execPath)
            process.arguments = []
        } else {
            NSApp.terminate(nil)
            return
        }
        try? process.run()
        NSApp.terminate(nil)
    }
}

