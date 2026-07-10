import AppKit
import FadeoCore

/// Frontmost-application sensor. Pure push: `NSWorkspace` posts a notification on every
/// app activation, so there is no polling and effectively zero idle cost. This is the
/// core trigger and the one wired end-to-end in M0.
@MainActor
final class AppFocusSensor: Sensor {
    static let providedFields: Set<ContextField> = [.app]

    private var observer: NSObjectProtocol?

    func start(emit: @escaping (ContextPatch) -> Void) {
        // Seed with the current frontmost app immediately.
        let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        emit(ContextPatch(apply: { $0.frontmostApp = current }, label: "app → \(current ?? "—")"))

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            let bundle = app?.bundleIdentifier
            MainActor.assumeIsolated {
                emit(ContextPatch(apply: { $0.frontmostApp = bundle }, label: "app → \(bundle ?? "—")"))
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
