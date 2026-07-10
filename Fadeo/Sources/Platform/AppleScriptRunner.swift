import Foundation

/// Runs a fixed AppleScript string synchronously. Never throws — the AppleEvents
/// permission prompt and any script error are logged, not surfaced as a crash, since a
/// user can decline Automation access at any time and Fadeo must keep running silently.
enum AppleScriptRunner {
    @discardableResult
    static func run(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("Fadeo: AppleScript failed: \(errorInfo)")
            return false
        }
        return true
    }
}
