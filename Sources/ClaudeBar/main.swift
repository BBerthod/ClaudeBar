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
    let overlayManager = OverlayManager()

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
            overlayManager: overlayManager
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Data

    private func loadInitialData() {
        projectService.reload(totalCostEstimate: statsService.totalCostEstimate)
        hookHealthService.analyze(settings: settingsService.settings)
        burnRateService.update(statsService: statsService)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.notificationService.checkCostThreshold(currentCost: self.statsService.todayCostEstimate)
            self.updateStatusLabel()
        }
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.burnRateService.update(statsService: self.statsService)
                self.notificationService.checkCostThreshold(currentCost: self.statsService.todayCostEstimate)
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

    private func updateStatusLabel() {
        guard let button = statusItem.button else { return }
        let tokens = statsService.todayTokens
        if tokens > 0 {
            button.title = " \(tokens.abbreviatedTokenCount)"
        } else {
            button.title = ""
        }
    }
}
