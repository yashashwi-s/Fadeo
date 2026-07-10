import Foundation

/// Generic transport control for "whatever app currently holds the Now Playing session"
/// — play/pause/next/previous, system-wide, without needing to know which app it is.
///
/// Since macOS 15.4, `mediaremoted` enforces entitlements on *reading* now-playing state,
/// but sending transport *commands* still works for unentitled processes (confirmed via
/// public reverse-engineering of MediaRemote.framework — see PLAN.md 1). We reach the
/// private framework via `dlopen`/`dlsym` rather than linking it, so a future OS that
/// removes or renames the symbol degrades to a silent no-op instead of a crash or a
/// launch-time link failure.
final class MediaRemoteBridge {
    private typealias SendCommandFn = @convention(c) (Int, AnyObject?) -> Bool

    private enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
        case nextTrack = 4
        case previousTrack = 5
    }

    private var sendCommand: SendCommandFn?

    init() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY
        ) else {
            NSLog("Fadeo: MediaRemote.framework unavailable — external transport control disabled")
            return
        }
        guard let sym = dlsym(handle, "MRMediaRemoteSendCommand") else {
            NSLog("Fadeo: MRMediaRemoteSendCommand symbol not found — external transport control disabled")
            return
        }
        sendCommand = unsafeBitCast(sym, to: SendCommandFn.self)
    }

    private func send(_ command: Command) {
        _ = sendCommand?(command.rawValue, nil)
    }

    func play() { send(.play) }
    func pause() { send(.pause) }
    func next() { send(.nextTrack) }
    func previous() { send(.previousTrack) }
}
