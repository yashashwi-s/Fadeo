import Foundation
import FadeoCore

/// A snapshot of exactly what was playing when Fadeo last quit gracefully (or was
/// paused), so the SAME workspace reappearing on a later launch resumes at the same
/// spot instead of restarting — a local file from the beginning, or an external app
/// re-cueing the share link from scratch. Ambient noise presets have no meaningful
/// position (a synthesized stream sounds identical whether "resumed" or restarted), so
/// they're never bookmarked. Only captured on a graceful quit
/// (`NSApplication.willTerminateNotification`) or an explicit pause — a force-quit or
/// crash loses the last few moments, an accepted tradeoff for not running a periodic
/// disk-write timer at every idle tick (see CLAUDE.md's efficiency contract).
struct PlaybackBookmark: Codable, Equatable {
    var workspaceID: String
    var source: String
    /// Internal file/folder/playlist sources only — which file in the queue.
    var queueIndex: Int?
    /// Internal file/folder/playlist sources only — elapsed seconds into that file.
    var positionSeconds: Double?
    var savedAt: Date
}

@MainActor
final class PlaybackBookmarkStore {
    private(set) var bookmark: PlaybackBookmark?

    init() {
        if let data = try? Data(contentsOf: AppPaths.playbackBookmarkFile) {
            bookmark = try? ConfigCodec.decodeAny(PlaybackBookmark.self, from: data)
        }
    }

    func save(_ bookmark: PlaybackBookmark) {
        self.bookmark = bookmark
        guard let data = try? ConfigCodec.encodeAny(bookmark) else { return }
        try? data.write(to: AppPaths.playbackBookmarkFile, options: .atomic)
    }

    /// Consumed once a resume has been attempted (successful or not) — a stale bookmark
    /// must not keep being retried on every subsequent config reload/relaunch.
    func clear() {
        guard bookmark != nil else { return }
        bookmark = nil
        try? FileManager.default.removeItem(at: AppPaths.playbackBookmarkFile)
    }
}
