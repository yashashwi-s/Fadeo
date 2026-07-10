import Foundation

/// Canonical on-disk locations. Config lives in Application Support so it survives app
/// updates and is easy to back up / version-control.
enum AppPaths {
    static let bundleId = "com.fadeo.Fadeo"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Fadeo", isDirectory: true)
    }

    static var configFile: URL {
        supportDirectory.appendingPathComponent("config.yaml")
    }

    static var usageFile: URL {
        supportDirectory.appendingPathComponent("usage.yaml")
    }

    /// Create the support directory if needed.
    static func ensureSupportDirectory() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }
}
