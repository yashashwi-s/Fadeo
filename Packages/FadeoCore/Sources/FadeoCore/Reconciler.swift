import Foundation

/// A snapshot of what audio is currently sounding. Owned by the actuator layer; the
/// Reconciler treats it as the "actual" against the resolver's "desired".
public struct AudioState: Sendable, Equatable {
    public var source: String?
    public var volume: Double
    public var playing: Bool
    /// The source ran to natural completion (repeat-off queue exhausted). Distinct from a
    /// failure: a finished play-once source must not restart on the next context tick.
    public var finished: Bool
    /// Held open in a resumable, silent state — not torn down, exact position (queue index,
    /// file playback position for internal files; the external app's own remembered
    /// position for Music/Spotify) preserved. Distinct from a full stop: reappearing on the
    /// SAME source resumes in place instead of restarting from the beginning.
    public var paused: Bool

    public init(source: String? = nil, volume: Double = 0, playing: Bool = false,
                finished: Bool = false, paused: Bool = false) {
        self.source = source
        self.volume = volume
        self.playing = playing
        self.finished = finished
        self.paused = paused
    }

    public static let silent = AudioState()
}

/// The minimal command needed to move `AudioState` toward a desired `AudioTarget`.
/// Emitting only the diff is what keeps Fadeo from re-issuing redundant fades/commands
/// on every context tick.
public enum AudioCommand: Sendable, Equatable {
    case none
    case start(source: String, volume: Double, fadeMs: Int)
    case crossfade(to: String, volume: Double, ms: Int)
    case setVolume(Double, ms: Int)
    /// Ramp to silence but hold the session open, resumable in place (see `AudioState.paused`).
    case pause(fadeMs: Int)
    /// Ramp back up in place — never re-schedules/re-cues, unlike `.start`.
    case resume(volume: Double, fadeMs: Int)
    case stop(fadeMs: Int)
}

/// Pure diff: (current, desired, transition) → one command. Fully unit-tested.
public struct Reconciler {
    public init() {}

    public func reconcile(current: AudioState, target: AudioTarget, transition: Transition) -> AudioCommand {
        let t = transition.timing
        switch target.action {
        case .doNothing, .resumePrevious:
            // "keep current" — never disturb what's playing (resumePrevious is handled by
            // the external conductor once wired; internally it's a no-op).
            return .none

        case .pause:
            // A workspace's own "Pause" is real and resumable now, distinct from "Stop" —
            // reappearing on the same source (a meeting ending, leaving a Reading app)
            // resumes exactly where it paused instead of restarting.
            guard current.playing else { return .none }
            return .pause(fadeMs: t.fadeOutMs)

        case .stop:
            // A deliberate stop must force a real teardown even from an already-paused
            // (silent but still held open) state — otherwise a workspace explicitly
            // configured to stop, arriving while something else is merely paused, would
            // silently leave that session sitting open instead of tearing it down.
            if current.paused, !target.resumable { return .stop(fadeMs: t.fadeOutMs) }
            guard current.playing else { return .none }
            // `target.resumable` is set only by a transient "nothing matches right now"
            // fallback decision (Resolver) that happens to use the `.stop` action — never
            // by a workspace's own configured stop action, which is always a hard stop.
            return target.resumable ? .pause(fadeMs: t.fadeOutMs) : .stop(fadeMs: t.fadeOutMs)

        case .setVolume, .duck:
            guard current.playing else { return .none }
            return volumeChanged(current.volume, target.volume) ? .setVolume(target.volume, ms: t.fadeInMs) : .none

        case .play:
            guard let src = target.source else {
                guard current.playing else { return .none }
                return target.resumable ? .pause(fadeMs: t.fadeOutMs) : .stop(fadeMs: t.fadeOutMs)
            }
            if current.finished, current.source == src, target.repeatMode == .off {
                return .none   // play-once queue already completed; a context tick must not restart it
            }
            if current.paused, current.source == src {
                return .resume(volume: target.volume, fadeMs: t.fadeInMs)   // exact-position resume, not a restart
            }
            if !current.playing {
                return .start(source: src, volume: target.volume, fadeMs: t.fadeInMs)
            }
            if current.source != src {
                return .crossfade(to: src, volume: target.volume, ms: t.crossfadeMs)
            }
            if volumeChanged(current.volume, target.volume) {
                return .setVolume(target.volume, ms: t.fadeInMs)
            }
            return .none
        }
    }

    private func volumeChanged(_ a: Double, _ b: Double) -> Bool { abs(a - b) > 0.001 }
}
