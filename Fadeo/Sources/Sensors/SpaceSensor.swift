import AppKit
import FadeoCore

/// Active Space (virtual desktop) sensor. `NSWorkspace.activeSpaceDidChangeNotification`
/// is the public, push-based trigger; `SpaceBridge` resolves *which* Space via private
/// symbols. If the bridge is unavailable, we still emit — with `index: nil` — so
/// app-based workspace matches keep working even when Space-by-index degrades.
@MainActor
final class SpaceSensor: Sensor {
    static let providedFields: Set<ContextField> = [.space]

    private var observer: NSObjectProtocol?

    func start(emit: @escaping (ContextPatch) -> Void) {
        emit(current())

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                emit(self.current())
            }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func current() -> ContextPatch {
        let index = SpaceBridge.currentSpaceIndex()
        let ref = SpaceRef(display: "main", index: index)
        return ContextPatch(
            apply: { $0.activeSpace = ref },
            label: "space → \(index.map(String.init) ?? "unknown")"
        )
    }
}
