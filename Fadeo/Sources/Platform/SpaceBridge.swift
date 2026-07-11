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

    /// Logged at most once per launch: repeated NSLog spam would just be noise once the
    /// private shape has changed (every subsequent call would hit the same nil path).
    private static var didLogFailure = false

    /// The 1-based index of the currently active Space on the main display, or `nil` if
    /// the private API is unavailable or its shape has changed on this macOS version.
    static func currentSpaceIndex() -> Int? {
        guard let index = uncachedCurrentSpaceIndex() else {
            if !didLogFailure {
                didLogFailure = true
                NSLog("Fadeo SpaceBridge: could not read current Space (private CGS shape changed?)")
            }
            return nil
        }
        return index
    }

    private static func uncachedCurrentSpaceIndex() -> Int? {
        guard let mainConnectionID, let copyManagedDisplaySpaces else { return nil }
        let cid = mainConnectionID()
        guard let displays = copyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        // "Display Identifier" is a per-display UUID, not a stable "Main" marker (verified
        // by inspection: there is no literal "Main" value to match. CGS orders the main
        // display first in practice, and this is single-display-correct regardless; true
        // per-display resolution is out of scope for v1 (see PLAN.md §19).
        guard let display = displays.first,
              let spaces = display["Spaces"] as? [[String: Any]],
              let current = display["Current Space"] as? [String: Any],
              let currentID = current["id64"] as? Int64 ?? (current["ManagedSpaceID"] as? NSNumber)?.int64Value
        else { return nil }

        // Real desktops report `type == 0`. Fullscreen/tiled-app spaces report `type == 4`
        // (verified live: they carry TileLayoutManager/WallSpace/fs_wid keys instead of a
        // Display Identifier) and must be excluded, or their presence in the raw array can
        // shift the 1-based index away from what Mission Control shows as "Desktop N".
        // Entries missing the `type` key entirely are kept, for compatibility with any CGS
        // shape where it's absent.
        let userSpaces = spaces.filter { ($0["type"] as? Int ?? 0) == 0 }

        for (i, space) in userSpaces.enumerated() {
            let id = space["id64"] as? Int64 ?? (space["ManagedSpaceID"] as? NSNumber)?.int64Value
            if id == currentID { return i + 1 }
        }
        return nil
    }
}
