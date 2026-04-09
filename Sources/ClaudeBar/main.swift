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
    let providerUsageService = ProviderUsageService()
    let mainWindowManager = MainWindowManager()
    let anomalyService = AnomalyService()

    private var refreshTimer: Timer?
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
        // Hide dock icon AFTER status item is created
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalHotkeyMonitor = nil
        }
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
                title: "Relancer ClaudeBar",
                action: #selector(relaunchApp),
                keyEquivalent: ""
            )
            relaunch.target = self
            menu.addItem(relaunch)
            menu.addItem(NSMenuItem.separator())
            let quit = NSMenuItem(
                title: "Quitter ClaudeBar",
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
            providerUsageService: providerUsageService,
            onRefresh: { [weak self] in self?.refreshAll() },
            onOpenDashboard: { [weak self] in self?.openAnalytics() }
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

    // MARK: - Global Hotkey

    private func setupGlobalHotkey() {
        // Cmd+Shift+C (keyCode 8 = 'c')
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains([.command, .shift]),
                  event.keyCode == 8 else { return }
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
                    self.notificationService.digestPending = false
                }
            }
        }
    }

    func restartRefreshTimer() {
        refreshTimer?.invalidate()
        startRefreshTimer()
    }

    /// Opens the full window — same content as the popover but in a persistent, resizable window.
    func openAnalytics() {
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
            providerUsageService: providerUsageService,
            onRefresh: { [weak self] in self?.refreshAll() }
        )
        mainWindowManager.show(content: contentView)
        // Close popover when opening the main window
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

        // Status bar indicator (opt-in, default off)
        if UserDefaults.standard.bool(forKey: "claudebar.showStatusBarIndicator") {
            let util = usageService.usage?.fiveHour?.utilization ?? 0
            let alert = util >= 80 ? " ⚠" : ""
            if cost > 0 {
                button.title = CostCalculator.formatCost(cost) + alert
            } else if sessions > 0 {
                button.title = "●" + alert
            } else {
                button.title = alert.isEmpty ? "" : alert
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
