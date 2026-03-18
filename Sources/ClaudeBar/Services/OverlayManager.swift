import AppKit
import SwiftUI

@Observable
@MainActor
final class OverlayManager {
    private var panel: NSPanel?
    private(set) var isVisible = false

    func toggle(sessionService: SessionService) {
        if isVisible {
            hide()
        } else {
            show(sessionService: sessionService)
        }
    }

    func show(sessionService: SessionService) {
        if panel == nil {
            createPanel(sessionService: sessionService)
        }
        panel?.orderFront(nil)
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    private func createPanel(sessionService: SessionService) {
        let content = FloatingOverlayContent(sessionService: sessionService)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 180, height: 300)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 300),
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

        // Position at top-right of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 200
            let y = screenFrame.maxY - 320
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
    }

    func updateSize(sessionCount: Int) {
        guard let panel else { return }
        let height = max(60, 40 + sessionCount * 30)
        var frame = panel.frame
        let oldHeight = frame.height
        frame.size.height = CGFloat(height)
        frame.origin.y += oldHeight - CGFloat(height) // Keep top edge fixed
        panel.setFrame(frame, display: true, animate: true)
    }
}
