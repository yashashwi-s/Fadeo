import AppKit
import FadeoCore

/// Frontmost-application sensor. Pure push: `NSWorkspace` posts a notification on every
/// app activation, so there is no polling and effectively zero idle cost. This is the
/// core trigger and the one wired end-to-end in M0.
///
/// Transient system UI (Mission Control/Dock, Spotlight, Notification Center, Control
/// Center) and Fadeo's own window/menu bar briefly becoming frontmost are NOT real app
/// switches from the user's point of view — clicking a menu bar item, glancing at Mission
/// Control, or opening Fadeo itself to check status must not read as "left the workspace"
/// and fade the audio out. Activations to any of these bundle IDs are simply dropped: no
/// patch is emitted, so `Context.frontmostApp` keeps whatever it last held and no
/// re-evaluation happens. (Confirmed live: no ignore-list like this existed anywhere in
/// this repo's history before — see the git log around this change.)
@MainActor
final class AppFocusSensor: Sensor {
    static let providedFields: Set<ContextField> = [.app]

    /// Bundle IDs whose activation is never treated as a real app switch.
    static let transientBundleIDs: Set<String> = [
        "com.fadeo.Fadeo",
        "com.apple.dock",              // hosts Mission Control / Exposé
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
    ]

    private var observer: NSObjectProtocol?

    func start(emit: @escaping (ContextPatch) -> Void) {
        // Seed with the current frontmost app immediately (skip if it's transient UI —
        // extremely unlikely at launch, but keep the same rule consistent everywhere).
        if let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           !Self.transientBundleIDs.contains(current) {
            emit(ContextPatch(apply: { $0.frontmostApp = current }, label: "app → \(current)"))
        }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            guard let bundle = app?.bundleIdentifier, !Self.transientBundleIDs.contains(bundle) else { return }
            MainActor.assumeIsolated {
                emit(ContextPatch(apply: { $0.frontmostApp = bundle }, label: "app → \(bundle)"))
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    deinit {
        // removeObserver is safe from any thread for block-based observers.
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
