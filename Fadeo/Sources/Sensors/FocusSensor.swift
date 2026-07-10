import Foundation
import FadeoCore

/// Reads the current macOS Focus/DND mode from `~/Library/DoNotDisturb/DB/Assertions.json`
/// — no public API exists for this. Push-based via FSEvents on the containing directory
/// (not the file — Focus changes rewrite it, not append). The identifier stored in
/// `Context.focusMode` is the raw `modeIdentifier` (e.g.
/// "com.apple.donotdisturb.mode.default", or a UUID for a custom user Focus) — stable
/// and exactly what `Match.focus` should reference, no hardcoded name mapping needed.
///
/// Schema confirmed by inspection of a real Assertions.json on this machine: when a Focus
/// is active, the most recent entry in `data` has a non-empty `storeAssertionRecords`
/// array whose first element's `assertionDetails.assertionDetailsModeIdentifier` names the
/// mode. When Focus is off, that key is absent (only invalidation records remain). This is
/// an undocumented, private file format — parsing fails safe to "no Focus" on any
/// unexpected shape rather than crashing.
@MainActor
final class FocusSensor: Sensor {
    static let providedFields: Set<ContextField> = [.focus]

    private static let dbDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    private static let assertionsFile = dbDirectory.appendingPathComponent("Assertions.json")

    private var watcher: FileWatcher?

    func start(emit: @escaping (ContextPatch) -> Void) {
        emitCurrent(emit)
        watcher = FileWatcher(directory: Self.dbDirectory) { [weak self] in
            Task { @MainActor in self?.emitCurrent(emit) }
        }
        watcher?.start()
    }

    func stop() {
        watcher?.stop()
        watcher = nil
    }

    private func emitCurrent(_ emit: @escaping (ContextPatch) -> Void) {
        let mode = Self.readActiveModeIdentifier()
        emit(ContextPatch(apply: { $0.focusMode = mode }, label: "focus → \(mode ?? "none")"))
    }

    /// One-shot read for the Workspace editor's "use current Focus" button. The UI
    /// doesn't need a running sensor, just the value at the moment of the click.
    static func currentModeIdentifierForUI() -> String? { readActiveModeIdentifier() }

    private static func readActiveModeIdentifier() -> String? {
        guard let data = try? Data(contentsOf: assertionsFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]],
              let latest = entries.last
        else { return nil }

        guard let records = latest["storeAssertionRecords"] as? [[String: Any]],
              let first = records.first,
              let details = first["assertionDetails"] as? [String: Any],
              let modeIdentifier = details["assertionDetailsModeIdentifier"] as? String
        else { return nil }

        return modeIdentifier
    }
}
