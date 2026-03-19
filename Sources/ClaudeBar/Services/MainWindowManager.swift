import AppKit
import SwiftUI

@Observable
@MainActor
final class MainWindowManager {
    private var window: NSWindow?
    private(set) var isVisible = false

    func toggle(content: some View) {
        if isVisible { hide() } else { show(content: content) }
    }

    func show(content: some View) {
        if window == nil { createWindow(content: content) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        isVisible = true
    }

    func hide() {
        window?.orderOut(nil)
        isVisible = false
    }

    private func createWindow(content: some View) {
        let hostingView = NSHostingView(rootView: AnyView(content))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "ClaudeBar"
        window.minSize = NSSize(width: 800, height: 500)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("com.claudebar.mainwindow")

        // Track close via notification
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.isVisible = false
        }

        self.window = window
    }
}
