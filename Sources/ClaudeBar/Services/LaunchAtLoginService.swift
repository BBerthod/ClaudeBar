import Foundation
import ServiceManagement

@Observable
@MainActor
final class LaunchAtLoginService {
    private(set) var isEnabled: Bool = false
    private(set) var isAvailable: Bool = false

    private enum DefaultsKey {
        static let launchAtLogin = "claudebar.launchAtLogin"
    }

    init() {
        isAvailable = Bundle.main.bundleIdentifier != nil
        guard isAvailable else { return }

        let status = SMAppService.mainApp.status
        if status == .enabled {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.launchAtLogin)
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: DefaultsKey.launchAtLogin)
        } catch {
            // Registration failed — Toggle snaps back automatically
        }
    }
}
