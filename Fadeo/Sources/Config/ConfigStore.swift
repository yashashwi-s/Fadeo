import Foundation
import Combine
import FadeoCore

/// Owns the on-disk config as the single source of truth. Creates a starter config on
/// first launch, publishes changes, and hot-reloads when the file changes underneath us
/// (GUI edits and hand-edits converge here). On a bad edit it keeps the last-good config
/// and surfaces the error instead of crashing or going silently broken.
@MainActor
final class ConfigStore: ObservableObject {
    @Published private(set) var config: Config
    @Published private(set) var lastError: String?
    @Published private(set) var lastLoaded: Date = Date()

    private var watcher: FileWatcher?
    /// Guards against reacting to our own writes.
    private var lastWrittenData: Data?

    init() {
        // Load or seed synchronously so the app never starts without a config.
        do {
            try AppPaths.ensureSupportDirectory()
            if FileManager.default.fileExists(atPath: AppPaths.configFile.path) {
                let data = try Data(contentsOf: AppPaths.configFile)
                self.config = try ConfigCodec.decode(data)
                self.lastWrittenData = data
            } else {
                self.config = .starter
                let data = try ConfigCodec.encode(.starter)
                try data.write(to: AppPaths.configFile, options: .atomic)
                self.lastWrittenData = data
            }
        } catch {
            self.config = .starter
            self.lastError = "Falling back to defaults: \(error.localizedDescription)"
        }
        startWatching()
    }

    private func startWatching() {
        watcher = FileWatcher(directory: AppPaths.supportDirectory) { [weak self] in
            Task { @MainActor in self?.reloadFromDisk() }
        }
        watcher?.start()
    }

    private func reloadFromDisk() {
        guard let data = try? Data(contentsOf: AppPaths.configFile) else { return }
        if data == lastWrittenData { return }  // our own write echoing back
        do {
            let decoded = try ConfigCodec.decode(data)
            lastWrittenData = data
            // Only republish on a genuine change, so unrelated activity in the directory
            // (or a byte-identical rewrite) never triggers a re-evaluation storm.
            guard decoded != config else { return }
            config = decoded
            lastError = nil
            lastLoaded = Date()
        } catch {
            // Keep the last-good config; report the problem. Notify once on the transition
            // into a bad state (not on every reload while it stays bad), since a direct edit
            // to config.yaml that fails to parse is otherwise silent.
            let wasGood = lastError == nil
            lastError = "config.yaml invalid, keeping last good version. \(error.localizedDescription)"
            if wasGood {
                Notifier.shared.notify(
                    title: "Fadeo: config.yaml didn't parse",
                    body: "Your last edit had an error. Fadeo kept the previous good config. Open Preferences to see details.",
                    id: "fadeo.config.error"
                )
            }
        }
    }

    /// Persist an in-memory edit (from the GUI) back to disk atomically. Regenerates the
    /// whole file from `newConfig`, which drops any hand-added comments — see `saveRaw`
    /// for the one path that doesn't.
    func save(_ newConfig: Config) {
        config = newConfig
        do {
            let data = try ConfigCodec.encode(newConfig)
            lastWrittenData = data
            try data.write(to: AppPaths.configFile, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Could not save config: \(error.localizedDescription)"
        }
    }

    /// Persist the Advanced pane's raw YAML text exactly as typed, comments and all —
    /// unlike `save(_:)`, this never re-encodes through `Config`, so a hand-written
    /// comment actually survives this save. `decoded` (already parsed by the caller, so a
    /// bad edit is reported before ever reaching here) becomes the new in-memory config.
    func saveRaw(text: String, decoded: Config) {
        config = decoded
        guard let data = text.data(using: .utf8) else {
            lastError = "Could not save config: text isn't valid UTF-8."
            return
        }
        do {
            lastWrittenData = data
            try data.write(to: AppPaths.configFile, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Could not save config: \(error.localizedDescription)"
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.configFile])
    }
}

#if canImport(AppKit)
import AppKit
#endif
