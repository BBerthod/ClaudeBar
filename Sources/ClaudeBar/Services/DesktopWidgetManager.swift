import AppKit
import SwiftUI

@Observable
@MainActor
final class DesktopWidgetManager {
    private var panel: NSPanel?
    private(set) var isVisible = false

    func toggle(usageService: UsageService, statsService: StatsService, sessionService: SessionService, liveStatsService: LiveStatsService) {
        if isVisible { hide() } else { show(usageService: usageService, statsService: statsService, sessionService: sessionService, liveStatsService: liveStatsService) }
    }

    func show(usageService: UsageService, statsService: StatsService, sessionService: SessionService, liveStatsService: LiveStatsService) {
        if panel == nil { createPanel(usageService: usageService, statsService: statsService, sessionService: sessionService, liveStatsService: liveStatsService) }
        panel?.orderFront(nil)
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    private func createPanel(usageService: UsageService, statsService: StatsService, sessionService: SessionService, liveStatsService: LiveStatsService) {
        let content = DesktopWidgetView(onClose: { [weak self] in self?.hide() })
            .environment(usageService)
            .environment(statsService)
            .environment(sessionService)
            .environment(liveStatsService)

        let hostingView = NSHostingView(rootView: content)
        hostingView.sizingOptions = .preferredContentSize
        let idealSize = hostingView.fittingSize
        let panelWidth: CGFloat = max(idealSize.width, 200)
        let panelHeight: CGFloat = max(idealSize.height, 100)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 220
            let y = screenFrame.minY + 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
    }
}
