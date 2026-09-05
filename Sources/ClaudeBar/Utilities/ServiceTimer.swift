import Foundation

/// Protects timer ownership so service teardown can invalidate from any executor.
final class ServiceTimer: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTimer: Timer?

    var timer: Timer? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedTimer
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedTimer?.invalidate()
            storedTimer = newValue
        }
    }

    func invalidate() {
        timer = nil
    }
}
