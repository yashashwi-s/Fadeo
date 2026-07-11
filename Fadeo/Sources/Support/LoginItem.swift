import Foundation
import ServiceManagement

/// Launch-at-login via the modern `SMAppService` API (macOS 13+) — no hand-written
/// LaunchAgent plist, no helper tool to install.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns whether registration actually succeeded, so a caller's optimistic UI
    /// toggle can resync to the real state on failure rather than silently showing "on"
    /// when `SMAppService.register()` didn't actually take (not uncommon for ad-hoc-
    /// signed/dev builds, or if the app isn't in a location SMAppService will trust).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("Fadeo: login item toggle failed: \(error.localizedDescription)")
        }
        return isEnabled == enabled
    }
}
