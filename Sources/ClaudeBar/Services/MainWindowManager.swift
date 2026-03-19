import AppKit
import SwiftUI

@Observable
@MainActor
final class MainWindowManager {
    private var window: NSWindow?
    // @ObservationIgnored + nonisolated(unsafe) lets deinit access this without
    // crossing the @MainActor boundary. It is only written on the main thread.
    @ObservationIgnored
    private nonisolated(unsafe) var closeObserver: (any NSObjectProtocol)?
    private(set) var isVisible = false

    deinit {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

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
        // Remove any previous observer before creating a new window.
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }

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

        // Store the observer token so it can be removed later.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isVisible = false
            }
        }

        self.window = window
    }
}
