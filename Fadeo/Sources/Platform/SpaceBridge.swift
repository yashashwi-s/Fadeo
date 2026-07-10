import Foundation
import CoreGraphics

/// Resolves the active Space (virtual desktop) index using private SkyLight/CGS symbols.
/// There is no public API for this (`NSWorkspace.activeSpaceDidChangeNotification` says
/// *a* Space changed, never *which*) — see PLAN.md finding 2. Reached via `dlopen`/`dlsym`
/// so a future macOS renaming or removing these symbols degrades to "index unknown"
/// rather than a crash or a launch-time link failure.
enum SpaceBridge {
    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static let mainConnectionID: MainConnectionIDFn? = {
        guard let handle, let sym = dlsym(handle, "CGSMainConnectionID") else { return nil }
        return unsafeBitCast(sym, to: MainConnectionIDFn.self)
    }()

    private static let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn? = {
        guard let handle, let sym = dlsym(handle, "CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(sym, to: CopyManagedDisplaySpacesFn.self)
    }()

    static var isAvailable: Bool { mainConnectionID != nil && copyManagedDisplaySpaces != nil }

    /// The 1-based index of the currently active Space on the main display, or `nil` if
    /// the private API is unavailable or its shape has changed on this macOS version.
    static func currentSpaceIndex() -> Int? {
        guard let mainConnectionID, let copyManagedDisplaySpaces else { return nil }
        let cid = mainConnectionID()
        guard let displays = copyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        // "Display Identifier" is a per-display UUID, not a stable "Main" marker (verified
        // by inspection — there is no literal "Main" value to match). CGS orders the main
        // display first in practice, and this is single-display-correct regardless; true
        // per-display resolution is out of scope for v1 (see PLAN.md §19).
        guard let display = displays.first,
              let spaces = display["Spaces"] as? [[String: Any]],
              let current = display["Current Space"] as? [String: Any],
              let currentID = current["id64"] as? Int64 ?? (current["ManagedSpaceID"] as? NSNumber)?.int64Value
        else { return nil }

        for (i, space) in spaces.enumerated() {
            let id = space["id64"] as? Int64 ?? (space["ManagedSpaceID"] as? NSNumber)?.int64Value
            if id == currentID { return i + 1 }
        }
        return nil
    }
}
