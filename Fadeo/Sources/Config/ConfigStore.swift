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
            // Keep the last-good config; report the problem.
            lastError = "config.yaml invalid, keeping last good version. \(error.localizedDescription)"
        }
    }

    /// Persist an in-memory edit (from the GUI) back to disk atomically.
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

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.configFile])
    }
}

#if canImport(AppKit)
import AppKit
#endif
