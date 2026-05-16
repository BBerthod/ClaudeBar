import AppKit

/// Single public surface exposed to the executable target.
/// All other types remain internal.
public func runApp() {
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.run()
}
