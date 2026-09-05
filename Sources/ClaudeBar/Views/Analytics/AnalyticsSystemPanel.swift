import SwiftUI
import AppKit

struct AnalyticsSystemPanel: View {
    @Environment(OmlxUsageService.self) private var omlxUsageService
    let statsService: StatsService
    let sessionService: SessionService
    let usageService: UsageService
    let mcpHealthService: McpHealthService
    let omlxMonitorService: OmlxMonitorService
    let providerUsageService: ProviderUsageService

    var body: some View {
        systemPanel
    }
    private var systemPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("System")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)

                // App info
                GroupBox("ClaudeBar") {
                    VStack(spacing: 0) {
                        systemInfoRow("Version", value: "1.0.0")
                        Divider().padding(.horizontal, 8)
                        systemInfoRow("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                        Divider().padding(.horizontal, 8)
                        systemInfoRow("Memory", value: memoryUsageString())
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                // OAuth / plan status
                GroupBox("Account") {
                    VStack(spacing: 0) {
                        systemInfoRow("Plan", value: usageService.plan.displayName)
                        Divider().padding(.horizontal, 8)
                        systemInfoRow("Rate Tier", value: usageService.tier.displayName)
                        Divider().padding(.horizontal, 8)
                        systemInfoRow(
                            "Token Status",
                            value: tokenStatusString(),
                            valueColor: tokenStatusColor()
                        )
                        if let lastFetched = usageService.lastFetched {
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Last API Fetch", value: lastFetched.formattedTime)
                        }
                        if let lastError = usageService.lastError {
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("API Error", value: lastError, valueColor: .red)
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                // Stats cache info
                GroupBox("Stats Cache") {
                    VStack(spacing: 0) {
                        if let stats = statsService.stats {
                            systemInfoRow("Last Computed", value: stats.lastComputedDate)
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Staleness", value: statsCacheStaleness(stats.lastComputedDate), valueColor: statsCacheStalenessColor(stats.lastComputedDate))
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Days of Data", value: "\(stats.dailyModelTokens.count) days")
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Total Sessions", value: "\(stats.totalSessions)")
                        } else {
                            Text("Stats cache not loaded")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                        }
                        if let lastError = statsService.lastError {
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Load Error", value: lastError, valueColor: .red)
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                // MCP servers
                GroupBox("MCP Servers") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("\(mcpHealthService.servers.count) configured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                mcpHealthService.checkAll()
                            } label: {
                                Label(
                                    mcpHealthService.isChecking ? "Checking…" : "Check All",
                                    systemImage: "arrow.clockwise"
                                )
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(mcpHealthService.isChecking)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                        if mcpHealthService.servers.isEmpty {
                            Text("No MCP servers configured")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                        } else {
                            Divider()

                            ForEach(mcpHealthService.servers) { server in
                                mcpServerRow(server)

                                if server.id != mcpHealthService.servers.last?.id {
                                    Divider().padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                // oMLX inference server
                GroupBox("oMLX — Local Inference") {
                    VStack(spacing: 0) {
                        systemInfoRow(
                            "Status",
                            value: omlxMonitorService.isOnline ? "Online ✓" : "Offline",
                            valueColor: omlxMonitorService.isOnline ? .green : .secondary
                        )
                        if omlxMonitorService.isOnline {
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Model", value: omlxMonitorService.defaultModel ?? "—")
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Models available", value: "\(omlxMonitorService.modelCount)")
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Loaded", value: "\(omlxMonitorService.loadedCount)")
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Memory", value: omlxMonitorService.memoryLabel)
                        }
                        if let checked = omlxMonitorService.lastChecked {
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Last check", value: checked.formattedTime)
                        }
                        if let err = omlxMonitorService.lastError {
                            Divider().padding(.horizontal, 8)
                            systemInfoRow("Error", value: err, valueColor: .red)
                        }
                        if omlxUsageService.isAvailable {
                            Divider().padding(.horizontal, 8)
                            omlxUsageDetails
                        }
                    }
                    .padding(4)

                    HStack {
                        Spacer()
                        Button("Refresh") {
                            Task { await omlxMonitorService.checkHealth() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                    }
                }
                .padding(.horizontal)

                // Quick actions
                GroupBox("Quick Actions") {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        quickActionButton(
                            "settings.json",
                            icon: "gear",
                            path: NSString(string: "~/.claude/settings.json").expandingTildeInPath
                        )
                        quickActionButton(
                            ".claude.json",
                            icon: "doc.badge.gearshape",
                            path: NSString(string: "~/.claude.json").expandingTildeInPath
                        )
                        quickActionButton(
                            "~/.claude folder",
                            icon: "folder.badge.person.crop",
                            path: NSString(string: "~/.claude").expandingTildeInPath
                        )
                        quickActionButton(
                            "Projects folder",
                            icon: "folder.fill.badge.person.crop",
                            path: NSString(string: "~/.claude/projects").expandingTildeInPath
                        )
                        Button {
                            launchClaudeInTerminal()
                        } label: {
                            Label("Launch Claude", systemImage: "terminal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            launchClaudeWithContinue()
                        } label: {
                            Label("claude --continue", systemImage: "arrow.uturn.backward.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                }
                .padding(.horizontal)
            }
        }
    }

    private var omlxUsageDetails: some View {
        @Bindable var usage = omlxUsageService
        return VStack(alignment: .leading, spacing: 10) {
            systemInfoRow("Requests today", value: "\(usage.today?.totals.requests ?? 0)")
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Model")
                        Text("Prompt")
                        Text("Completion")
                        Text("Requests")
                        Text("tok/s")
                        Text("Last access")
                    }
                    .foregroundStyle(.secondary)
                    ForEach(usage.today?.perModel ?? []) { model in
                        GridRow {
                            Text(model.model)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: 180, alignment: .leading)
                                .help(model.model)
                            Text(model.promptTokens.abbreviatedTokenCount)
                            Text(model.completionTokens.abbreviatedTokenCount)
                            Text("\(model.requests)")
                            Text(model.generationTokensPerSecond, format: .number.precision(.fractionLength(1)))
                            Text(usage.loadedModels.first { $0.id == model.model }?.lastAccess?.timeAgoString ?? "—")
                        }
                    }
                }
                .font(.caption)
                .monospacedDigit()
            }
            if usage.today?.perModel.isEmpty != false {
                Text("No usage recorded today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Reference model", selection: $usage.referenceModelId) {
                Text("Sonnet 5").tag("claude-sonnet-5")
                Text("Opus 5").tag("claude-opus-5")
                Text("Haiku 4.5").tag("claude-haiku-4-5")
                Text("Fable 5.1").tag("claude-fable-5-1")
            }
            .controlSize(.small)
            systemInfoRow("Local cost today", value: "$0")
            systemInfoRow("API-equivalent today", value: "≈ \(CostCalculator.formatCost(usage.todayApiEquivalentCost))")
                .help("API-equivalent cost if these tokens had gone to \(usage.referenceModelId)")
            if let totals = usage.allTime {
                Text("All time: \(totals.totalRequests) requests · \(totals.totalPromptTokens.abbreviatedTokenCount) prompt · \(totals.totalCompletionTokens.abbreviatedTokenCount) completion · \(totals.totalCachedTokens.abbreviatedTokenCount) cached tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = usage.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private func systemInfoRow(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func mcpServerRow(_ server: McpServerInfo) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(server.status.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(server.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(server.endpoint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(server.status.label)
                .font(.caption)
                .foregroundStyle(server.status.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(server.status.color.opacity(0.1))
                .clipShape(Capsule())

            Text(server.type)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }


    @ViewBuilder
    private func quickActionButton(_ label: String, icon: String, path: String) -> some View {
        Button {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.open(url)
        } label: {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func launchClaudeInTerminal() {
        launchClaude(flags: [])
    }

    private func launchClaudeWithContinue() {
        launchClaude(flags: ["--continue"])
    }

    /// Launches claude in Terminal.app using the safe ARGV pattern.
    private func launchClaude(flags: [String]) {
        var parts = ["claude"]
        parts.append(contentsOf: flags)
        let command = parts.joined(separator: " ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "on run argv",
            "-e", "tell application \"Terminal\"",
            "-e", "    activate",
            "-e", "    do script (item 1 of argv)",
            "-e", "end tell",
            "-e", "end run",
            "--", command
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: - System helpers

    private func memoryUsageString() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return "Unknown" }
        let megabytes = Double(info.resident_size) / (1024 * 1024)
        return String(format: "%.1f MB", megabytes)
    }

    private func tokenStatusString() -> String {
        guard usageService.lastFetched != nil else { return "No token / not fetched" }
        if let error = usageService.lastError {
            if error.contains("401") || error.contains("expired") { return "Expired" }
            return "Error: \(error)"
        }
        return "Valid"
    }

    private func tokenStatusColor() -> Color {
        guard usageService.lastFetched != nil else { return .secondary }
        if let error = usageService.lastError {
            if error.contains("401") || error.contains("expired") { return .red }
            return .orange
        }
        return .green
    }

    private func statsCacheStaleness(_ dateString: String) -> String {
        guard let date = DateFormatter.isoDate.date(from: dateString) else { return "Unknown" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return "Fresh (today)" }
        if days == 1 { return "1 day old" }
        return "\(days) days old"
    }

    private func statsCacheStalenessColor(_ dateString: String) -> Color {
        guard let date = DateFormatter.isoDate.date(from: dateString) else { return .secondary }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return .green }
        if days == 1 { return .orange }
        return .red
    }
}

