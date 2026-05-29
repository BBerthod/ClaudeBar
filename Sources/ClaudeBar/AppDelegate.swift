import AppKit
import SwiftUI

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    // Detect Claude config dir once at class init (before any service uses it)
    private static let claudeDir: String = ClaudeDirectoryDetector.detect()

    // Services
    lazy var statsService: StatsService = StatsService(claudeDir: AppDelegate.claudeDir)
    lazy var sessionService: SessionService = SessionService(claudeDir: AppDelegate.claudeDir)
    lazy var settingsService: SettingsService = SettingsService(claudeDir: AppDelegate.claudeDir)
    lazy var projectService: ProjectService = ProjectService(claudeDir: AppDelegate.claudeDir)
    let hookHealthService = HookHealthService()
    let burnRateService = BurnRateService()
    let notificationService = NotificationService()
    let usageService = UsageService()
    lazy var liveStatsService: LiveStatsService = LiveStatsService(claudeDir: AppDelegate.claudeDir)
    let overlayManager = OverlayManager()
    let desktopWidgetManager = DesktopWidgetManager()
    let launchAtLoginService = LaunchAtLoginService()
    let mcpHealthService = McpHealthService()
    lazy var providerUsageService: ProviderUsageService = ProviderUsageService(
        claudeDir: AppDelegate.claudeDir
    )
    let mainWindowManager = MainWindowManager()
    let anomalyService = AnomalyService()
    lazy var yearlyHistoryService: YearlyHistoryService = YearlyHistoryService(claudeDir: AppDelegate.claudeDir)
    let updateCheckService = UpdateCheckService()
    let autoUpdater = AutoUpdater()
    let omlxMonitorService = OmlxMonitorService()

    private var refreshTimer: Timer?
    private var updateCheckTimer: Timer?
    private var historyRefreshTimer: Timer?
    private var globalHotkeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        loadInitialData()
        startRefreshTimer()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            // queue: .main guarantees we are already on the main actor
            MainActor.assumeIsolated {
                self.restartRefreshTimer()
            }
        }
        setupGlobalHotkey()
        startUpdateCheckTimer()
        startHistoryRefreshTimer()
        // Hide dock icon AFTER status item is created (respect user preference)
        let showDockIcon = UserDefaults.standard.bool(forKey: "claudebar.showDockIcon")
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalHotkeyMonitor = nil
        }
        updateCheckTimer?.invalidate()
        historyRefreshTimer?.invalidate()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "com.claudebar.statusitem"

        guard let button = statusItem.button else { return }

        if let img = NSImage(systemSymbolName: "brain", accessibilityDescription: "ClaudeBar") {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = false   // allow custom tint based on utilization
            button.image = img
        } else {
            button.title = "CB"
        }

        button.action = #selector(handleStatusItemClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let relaunch = NSMenuItem(
                title: "Relaunch ClaudeBar",
                action: #selector(relaunchApp),
                keyEquivalent: ""
            )
            relaunch.target = self
            menu.addItem(relaunch)
            menu.addItem(NSMenuItem.separator())
            let quit = NSMenuItem(
                title: "Quit ClaudeBar",
                action: #selector(quitApp),
                keyEquivalent: ""
            )
            quit.target = self
            menu.addItem(quit)
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func relaunchApp() {
        guard let execPath = Bundle.main.executablePath else {
            NSApp.terminate(nil)
            return
        }
        let process = Process()
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [bundlePath]
        } else {
            process.executableURL = URL(fileURLWithPath: execPath)
            process.arguments = []
        }
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: - Popover

    private func setupPopover() {
        let contentView = ContentView(
            onRefresh: { [weak self] in self?.refreshAll() },
            onOpenDashboard: { [weak self] in self?.openAnalytics() }
        )
        .environment(statsService)
        .environment(sessionService)
        .environment(settingsService)
        .environment(projectService)
        .environment(hookHealthService)
        .environment(burnRateService)
        .environment(notificationService)
        .environment(usageService)
        .environment(liveStatsService)
        .environment(overlayManager)
        .environment(desktopWidgetManager)
        .environment(launchAtLoginService)
        .environment(mcpHealthService)
        .environment(providerUsageService)
        .environment(yearlyHistoryService)
        .environment(updateCheckService)
        .environment(omlxMonitorService)

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

    // MARK: - Global Hotkey

    private func setupGlobalHotkey() {
        // Cmd+Shift+C — use charactersIgnoringModifiers for layout-agnostic matching
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains([.command, .shift]),
                  event.charactersIgnoringModifiers?.lowercased() == "c" else { return }
            Task { @MainActor in
                self?.togglePopover()
            }
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
        let interval = UserDefaults.standard.double(forKey: "claudebar.refreshInterval")
        let effectiveInterval = interval > 0 ? interval : 30
        refreshTimer = Timer.scheduledTimer(withTimeInterval: effectiveInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.burnRateService.update(statsService: self.statsService, liveStatsService: self.liveStatsService)
                if let fiveHour = self.usageService.usage?.fiveHour {
                    self.notificationService.checkUsageThreshold(
                        fiveHourUtilization: fiveHour.utilization,
                        resetKey: fiveHour.resetsAt
                    )
                }
                self.updateStatusLabel()
                let defaults = UserDefaults.standard
                let ctxThreshold = defaults.object(forKey: "claudebar.contextAlertThreshold") == nil
                    ? 90
                    : defaults.double(forKey: "claudebar.contextAlertThreshold")
                self.notificationService.checkContextThresholds(
                    activeSessions: self.sessionService.activeSessions,
                    contextEstimates: self.sessionService.contextEstimates,
                    thresholdPercent: ctxThreshold
                )
                self.anomalyService.check(burnRateService: self.burnRateService, notificationService: self.notificationService)

                if self.notificationService.digestPending {
                    self.notificationService.sendDailyDigest(
                        sessions: self.statsService.todaySessions,
                        messages: self.statsService.todayMessages,
                        tokens: self.statsService.todayTokens,
                        cost: self.statsService.todayCostEstimate,
                        topProject: self.projectService.projects.first?.projectName,
                        burnZone: self.burnRateService.burnRate?.zone
                    )
                    self.notificationService.markDigestSent()
                }
            }
        }
    }

    func restartRefreshTimer() {
        refreshTimer?.invalidate()
        startRefreshTimer()
    }

    // MARK: - Auto-Update

    private func startUpdateCheckTimer() {
        // Hourly repeat
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.updateCheckService.checkForUpdate()
                await self.installUpdateIfAvailable()
            }
        }
        // Explicit startup check — sequential, no timing assumption
        Task { @MainActor in
            await updateCheckService.checkForUpdate()
            await installUpdateIfAvailable()
        }
    }

    // MARK: - History Precompute + Background Refresh

    private func startHistoryRefreshTimer() {
        // Precompute at launch so the history view is instant when opened.
        Task { @MainActor in await yearlyHistoryService.load() }
        // Refresh every 10 minutes in the background.
        historyRefreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.yearlyHistoryService.refresh() }
        }
    }

    private func installUpdateIfAvailable() async {
        guard updateCheckService.updateAvailable,
              let url = updateCheckService.assetDownloadURL,
              !autoUpdater.isUpdating else { return }
        Log.stats.info("AppDelegate: triggering update to \(self.updateCheckService.latestVersion ?? "?")")
        await autoUpdater.downloadAndInstall(from: url)
    }

    /// Opens the full analytics window with NavigationSplitView layout.
    func openAnalytics() {
        let analyticsView = AnalyticsView()
            .environment(statsService)
            .environment(sessionService)
            .environment(burnRateService)
            .environment(usageService)
            .environment(liveStatsService)
            .environment(mcpHealthService)
            .environment(projectService)
            .environment(updateCheckService)
            .environment(providerUsageService)
            .environment(omlxMonitorService)
        mainWindowManager.show(content: analyticsView)
        popover?.performClose(nil)
    }

    /// Manual refresh — triggers the same update cycle as the 30s timer.
    func refreshAll() {
        liveStatsService.updateIfNeeded(statsService: statsService)
        burnRateService.update(statsService: statsService, liveStatsService: liveStatsService)
        projectService.reload(totalCostEstimate: statsService.totalCostEstimate)
        Task { await usageService.fetchUsage() }
    }

    private func updateStatusLabel() {
        guard let button = statusItem.button else { return }

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

        // Status bar indicator (opt-in, default off): 5h limit forecast + reset
        // countdown — e.g. "~1h38 → ↻2h10" (on pace to hit the limit) or "↻2h10".
        if UserDefaults.standard.bool(forKey: "claudebar.showStatusBarIndicator") {
            if let fiveHour = usageService.usage?.fiveHour, let resetDate = fiveHour.resetDate {
                button.title = UsageForecast.statusBarText(
                    utilization: fiveHour.utilization,
                    elapsedFraction: usageService.fiveHourElapsedFraction,
                    secondsRemaining: max(resetDate.timeIntervalSinceNow, 0)
                )
            } else if sessions > 0 {
                button.title = "●"
            } else {
                button.title = ""
            }
        } else {
            button.title = ""
        }

        let util = usageService.usage?.fiveHour?.utilization ?? 0
        button.contentTintColor = iconColor(for: util)

        // Cost alert threshold check
        let threshold = UserDefaults.standard.double(forKey: "claudebar.costAlertThreshold")
        if threshold > 0 && cost >= threshold {
            notificationService.sendCostAlertIfNeeded(cost: cost, threshold: threshold)
        }
    }

    private func iconColor(for utilization: Double) -> NSColor {
        // Default true — only disable if explicitly set to false
        let tintingEnabled = UserDefaults.standard.object(forKey: "claudebar.showIconTinting") as? Bool ?? true
        guard tintingEnabled else { return NSColor.controlTextColor }
        switch utilization {
        case ..<50:   return NSColor.controlTextColor
        case 50..<80: return NSColor.systemOrange
        default:      return NSColor.systemRed
        }
    }
}
