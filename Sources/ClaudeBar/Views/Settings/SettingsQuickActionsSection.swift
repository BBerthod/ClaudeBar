import SwiftUI
import AppKit

struct SettingsQuickActionsSection: View {
    let statsService: StatsService

    var body: some View {
        quickActionsSection
    }
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

                Divider()

                // Data export
                Menu {
                    Button("Export as CSV") {
                        ExportService.export(statsService: statsService, format: .csv)
                    }
                    Button("Export as JSON") {
                        ExportService.export(statsService: statsService, format: .json)
                    }
                } label: {
                    Label("Export Data", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .menuStyle(.borderlessButton)
                .disabled(statsService.stats == nil)
            }
            .padding(8)
        } label: {
            SettingsSectionLabel("Quick Actions")
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

}

