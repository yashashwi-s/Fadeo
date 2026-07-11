import Foundation
import FadeoCore

/// Local, on-device usage statistics. Entirely separate from the opt-in sharing
/// preference (see OnboardingSheet / PreferencesPane): this file exists and is populated
/// regardless, because it's useful to the user directly (their own "screen time for
/// sound"). Sharing a coarse summary is a separate, explicit choice that touches nothing
/// here except reading `stats.shareableSummary`.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var stats: UsageStats

    /// Batches disk writes rather than saving on every single accumulation, since
    /// workspace switches can be frequent (app-switching bursts) and this isn't the kind
    /// of state that needs to survive a crash to the second.
    private var dirty = false
    private var saveTimer: Timer?

    init() {
        if let data = try? Data(contentsOf: AppPaths.usageFile),
           let decoded = try? ConfigCodec.decodeAny(UsageStats.self, from: data) {
            stats = decoded
        } else {
            stats = UsageStats()
        }
        stats.sessionCount += 1
        dirty = true
        scheduleSave()
    }

    func recordActivation(workspaceID: String) {
        stats.recordActivation(workspaceID: workspaceID)
        dirty = true
        scheduleSave()
    }

    func recordElapsed(workspaceID: String?, seconds: Double) {
        guard seconds > 0.5 else { return }   // ignore sub-second noise from rapid app-switch bursts
        stats.recordElapsed(workspaceID: workspaceID, seconds: seconds, endedAt: Date())
        dirty = true
        scheduleSave()
    }

    /// Coalesces frequent updates into an occasional write rather than hitting disk on
    /// every app-focus change (which can fire many times a minute).
    private func scheduleSave() {
        guard saveTimer == nil else { return }
        saveTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    /// Drops usage rows for workspace ids that no longer exist in config, so a renamed or
    /// deleted workspace doesn't leave a stale row behind forever.
    func prune(keeping ids: Set<String>) {
        let before = stats.perWorkspace.count
        stats.perWorkspace = stats.perWorkspace.filter { ids.contains($0.key) }
        guard stats.perWorkspace.count != before else { return }
        dirty = true
        scheduleSave()
    }

    func flush() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard dirty else { return }
        dirty = false
        guard let data = try? ConfigCodec.encodeAny(stats) else { return }
        try? data.write(to: AppPaths.usageFile, options: .atomic)
    }
}
