import AppKit

/// Implements the **dual activation policy**: Fadeo runs as a `.accessory` menu-bar agent
/// (no Dock icon, App-Nap-friendly) in steady state, and becomes a `.regular` full app —
/// Dock icon, menus, standard window — only while a real window is open. This is what
/// lets Fadeo be both "a real full app" and "an invisible background daemon".
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(windowsChanged),
                       name: NSWindow.didBecomeKeyNotification, object: nil)
        nc.addObserver(self, selector: #selector(windowsChanged),
                       name: NSWindow.willCloseNotification, object: nil)

        // SwiftUI opens the `Window` scene at launch; close it so we start menu-bar-only —
        // unless this is the very first launch (onboarding needs the window) or the
        // screenshot-verification dev hook FADEO_OPEN_MAIN_ON_LAUNCH=1 is set.
        let keepOpen = !OnboardingSheet.hasCompleted
            || ProcessInfo.processInfo.environment["FADEO_OPEN_MAIN_ON_LAUNCH"] == "1"
        DispatchQueue.main.async { [weak self] in
            if !keepOpen {
                for w in NSApp.windows where Self.isAppWindow(w) { w.close() }
            }
            self?.updatePolicy()
        }
    }

    @objc private func windowsChanged() {
        // willClose fires before the window leaves the list; defer a tick so the count is right.
        DispatchQueue.main.async { [weak self] in self?.updatePolicy() }
    }

    private func updatePolicy() {
        let hasWindow = NSApp.windows.contains { $0.isVisible && Self.isAppWindow($0) }
        NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
        if hasWindow { NSApp.activate(ignoringOtherApps: true) }
    }

    /// A standard titled app window (excludes the MenuBarExtra's status window & popovers).
    private static func isAppWindow(_ w: NSWindow) -> Bool {
        w.styleMask.contains(.titled) && !(w is NSPanel)
    }

    // Re-open the main window when the user clicks the (now-visible) Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for w in NSApp.windows where Self.isAppWindow(w) { w.makeKeyAndOrderFront(nil) }
        }
        return true
    }
}
