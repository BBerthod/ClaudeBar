import AppKit
import SwiftUI

@Observable
@MainActor
final class DesktopWidgetManager {
    private var panel: NSPanel?
    private(set) var isVisible = false

    func toggle(usageService: UsageService, statsService: StatsService, sessionService: SessionService) {
        if isVisible { hide() } else { show(usageService: usageService, statsService: statsService, sessionService: sessionService) }
    }

    func show(usageService: UsageService, statsService: StatsService, sessionService: SessionService) {
        if panel == nil { createPanel(usageService: usageService, statsService: statsService, sessionService: sessionService) }
        panel?.orderFront(nil)
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    private func createPanel(usageService: UsageService, statsService: StatsService, sessionService: SessionService) {
        let content = DesktopWidgetView(onClose: { [weak self] in self?.hide() })
            .environment(usageService)
            .environment(statsService)
            .environment(sessionService)

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 120)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
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
