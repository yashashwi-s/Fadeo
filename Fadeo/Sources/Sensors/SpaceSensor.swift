import AppKit
import FadeoCore

/// Active Space (virtual desktop) sensor. `NSWorkspace.activeSpaceDidChangeNotification`
/// is the public, push-based trigger; `SpaceBridge` resolves *which* Space via private
/// symbols. If the bridge is unavailable, we still emit — with `index: nil` — so
/// app-based workspace matches keep working even when Space-by-index degrades.
///
/// Also re-queries on every app activation (`didActivateApplicationNotification`) as a
/// belt-and-braces refresh: on this macOS 27 beta, whether `activeSpaceDidChangeNotification`
/// reliably fires per-switch could not be confirmed live (no interactive desktop switch was
/// observed during testing), so a second, independent trigger keeps the index from freezing
/// if the primary one is flaky. This is free in the common case: `emit` only fires when the
/// resolved index actually changed, so an app switch within the same Space costs a cheap CGS
/// query and nothing downstream. A genuine Space switch with no app activation (e.g. an
/// idle desktop) still depends solely on the primary notification.
@MainActor
final class SpaceSensor: Sensor {
    static let providedFields: Set<ContextField> = [.space]

    private var spaceObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var lastEmittedIndex: Int??   // nil = never emitted; .some(nil) = emitted "unknown"

    func start(emit: @escaping (ContextPatch) -> Void) {
        lastEmittedIndex = nil
        emitIfChanged(emit)   // seed always emits (lastEmittedIndex starts nil)

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.emitIfChanged(emit)
            }
        }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.emitIfChanged(emit)
            }
        }
    }

    func stop() {
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        if let appActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver) }
        spaceObserver = nil
        appActivationObserver = nil
        lastEmittedIndex = nil
    }

    deinit {
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        if let appActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver) }
    }

    private func emitIfChanged(_ emit: (ContextPatch) -> Void) {
        let index = SpaceBridge.currentSpaceIndex()
        if let last = lastEmittedIndex, last == index { return }
        lastEmittedIndex = index
        let ref = SpaceRef(display: "main", index: index)
        emit(ContextPatch(
            apply: { $0.activeSpace = ref },
            label: "space → \(index.map(String.init) ?? "unknown")"
        ))
    }
}
