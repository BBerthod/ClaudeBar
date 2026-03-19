import AppKit
import SwiftUI

// Pure AppKit entry point — no SwiftUI App protocol
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    // Services
    let statsService = StatsService()
    let sessionService = SessionService()
    let settingsService = SettingsService()
    let projectService = ProjectService()
    let hookHealthService = HookHealthService()
    let burnRateService = BurnRateService()
    let notificationService = NotificationService()
    let usageService = UsageService()
    let liveStatsService = LiveStatsService()
    let overlayManager = OverlayManager()
    let desktopWidgetManager = DesktopWidgetManager()
    let launchAtLoginService = LaunchAtLoginService()
    let mcpHealthService = McpHealthService()

    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        loadInitialData()
        startRefreshTimer()
        // Hide dock icon AFTER status item is created
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "com.claudebar.statusitem"

        guard let button = statusItem.button else { return }

        if let img = NSImage(systemSymbolName: "brain", accessibilityDescription: "ClaudeBar") {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            button.image = img
        } else {
            button.title = "CB"
        }

        button.action = #selector(togglePopover)
        button.target = self
    }

    // MARK: - Popover

    private func setupPopover() {
        let contentView = ContentView(
            statsService: statsService,
            sessionService: sessionService,
            settingsService: settingsService,
            projectService: projectService,
            hookHealthService: hookHealthService,
            burnRateService: burnRateService,
            notificationService: notificationService,
            usageService: usageService,
            liveStatsService: liveStatsService,
            overlayManager: overlayManager,
            desktopWidgetManager: desktopWidgetManager,
            launchAtLoginService: launchAtLoginService,
            mcpHealthService: mcpHealthService,
            onRefresh: { [weak self] in self?.refreshAll() }
        )

        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Activate BEFORE showing — .accessory apps lose focus instantly otherwise,
            // causing the .transient popover to dismiss immediately.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Data

    private func loadInitialData() {
        projectService.reload(totalCostEstimate: statsService.totalCostEstimate)
        hookHealthService.analyze(settings: settingsService.settings)
        burnRateService.update(statsService: statsService, liveStatsService: liveStatsService)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.liveStatsService.updateIfNeeded(statsService: self.statsService)
            self.notificationService.checkCostThreshold(currentCost: self.statsService.todayCostEstimate)
            if let fiveHour = self.usageService.usage?.fiveHour {
                self.notificationService.checkUsageThreshold(
                    fiveHourUtilization: fiveHour.utilization,
                    resetKey: fiveHour.resetsAt
                )
            }
            self.updateStatusLabel()
        }
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.burnRateService.update(statsService: self.statsService, liveStatsService: self.liveStatsService)
                self.notificationService.checkCostThreshold(currentCost: self.statsService.todayCostEstimate)
                if let fiveHour = self.usageService.usage?.fiveHour {
                    self.notificationService.checkUsageThreshold(
                        fiveHourUtilization: fiveHour.utilization,
                        resetKey: fiveHour.resetsAt
                    )
                }
                self.updateStatusLabel()

                if self.notificationService.digestPending {
                    self.notificationService.sendDailyDigest(
                        sessions: self.statsService.todaySessions,
                        messages: self.statsService.todayMessages,
                        tokens: self.statsService.todayTokens,
                        cost: self.statsService.todayCostEstimate,
                        topProject: self.projectService.projects.first?.projectName,
                        burnZone: self.burnRateService.burnRate?.zone
                    )
                    self.notificationService.digestPending = false
                }
            }
        }
    }

    /// Manual refresh — triggers the same update cycle as the 30s timer.
    func refreshAll() {
        liveStatsService.updateIfNeeded(statsService: statsService)
        burnRateService.update(statsService: statsService, liveStatsService: liveStatsService)
        projectService.reload(totalCostEstimate: statsService.totalCostEstimate)
        notificationService.checkCostThreshold(currentCost: statsService.todayCostEstimate)
        Task { await usageService.fetchUsage() }
    }

    private func updateStatusLabel() {
        guard let button = statusItem.button else { return }
        button.title = ""

        // Hover tooltip: quick glance without opening the popover
        let msgs = statsService.todayMessages > 0 ? statsService.todayMessages : liveStatsService.todayMessages
        let cost = statsService.todayCostEstimate > 0 ? statsService.todayCostEstimate : liveStatsService.todayCost
        let sessions = sessionService.activeSessions.count
        let pct = usageService.usage?.fiveHour.map { "\(Int($0.utilization))% 5h" } ?? ""

        var parts: [String] = []
        if msgs > 0 { parts.append("\(msgs) msgs") }
        if cost > 0 { parts.append(CostCalculator.formatCost(cost)) }
        if sessions > 0 { parts.append("\(sessions) active") }
        if !pct.isEmpty { parts.append(pct) }

        button.toolTip = parts.isEmpty ? "ClaudeBar — No activity today" : parts.joined(separator: " · ")
    }
}
