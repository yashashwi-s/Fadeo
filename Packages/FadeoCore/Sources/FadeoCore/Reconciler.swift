import Foundation

/// A snapshot of what audio is currently sounding. Owned by the actuator layer; the
/// Reconciler treats it as the "actual" against the resolver's "desired".
public struct AudioState: Sendable, Equatable {
    public var source: String?
    public var volume: Double
    public var playing: Bool

    public init(source: String? = nil, volume: Double = 0, playing: Bool = false) {
        self.source = source
        self.volume = volume
        self.playing = playing
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

        case .pause, .stop:
            return current.playing ? .stop(fadeMs: t.fadeOutMs) : .none

        case .setVolume, .duck:
            guard current.playing else { return .none }
            return volumeChanged(current.volume, target.volume) ? .setVolume(target.volume, ms: t.fadeInMs) : .none

        case .play:
            guard let src = target.source else {
                return current.playing ? .stop(fadeMs: t.fadeOutMs) : .none
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
