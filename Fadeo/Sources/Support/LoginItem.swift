import Foundation
import ServiceManagement

/// Launch-at-login via the modern `SMAppService` API (macOS 13+) — no hand-written
/// LaunchAgent plist, no helper tool to install.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
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
    }
}
