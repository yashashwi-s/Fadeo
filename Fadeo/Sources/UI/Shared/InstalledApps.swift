import AppKit

/// A minimal app reference for pickers — bundle id plus a display name and icon, sourced
/// from `/Applications` and `~/Applications` (a directory scan, not a live enumeration —
/// this is a UI convenience, not a sensor, so it doesn't need to be push-based).
struct InstalledApp: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String

    var icon: NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .application)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum InstalledApps {
    /// Scans standard application directories once. Cheap relative to a UI picker's
    /// lifetime; not something the always-running daemon calls.
    static func scan() -> [InstalledApp] {
        var results: [String: InstalledApp] = [:]
        let dirs = [
            "/Applications",
            "/System/Applications",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
        ]
        for dir in dirs {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = dir + "/" + item
                guard let bundle = Bundle(path: path), let id = bundle.bundleIdentifier else { continue }
                let name = (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? (item as NSString).deletingPathExtension
                results[id] = InstalledApp(bundleID: id, name: name)
            }
        }
        return results.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The frontmost app right now — used for "capture frontmost app" in the match editor.
    static func frontmost() -> InstalledApp? {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier else { return nil }
        return InstalledApp(bundleID: id, name: app.localizedName ?? id)
    }
}
