import Foundation
import FadeoCore

/// Conducts a player you already use, rather than playing audio itself. Two layers:
/// - Generic transport (works for whichever app currently holds Now Playing, without
///   needing to know which one) via `MediaRemoteBridge` — no Automation permission needed.
/// - App-specific targeting (switch to a named playlist, set that app's own volume) via
///   AppleScript — requires the user to grant Automation access on first use; declining
///   just means playlist-targeting silently no-ops, transport control still works.
///
/// Source grammar (see PLAN.md §4):
///   external:command                    — play/pause whatever's currently cued, any app
///   external:appleMusic:command         — same, explicitly through Music.app
///   external:appleMusic:playlist:<name> — switch Music.app to that playlist
///   external:spotify:command            — same, explicitly through Spotify
///   external:spotify:playlist:<uri>     — switch Spotify to that playlist (Spotify URI)
final class ExternalConductor {
    private enum Target {
        case generic
        case appleMusic(playlist: String?)
        case spotify(playlist: String?)
    }

    private let mediaRemote = MediaRemoteBridge()
    private(set) var state: AudioState = .silent

    // MARK: Command execution

    func execute(_ command: AudioCommand) {
        switch command {
        case .none:
            break
        case .start(let source, let volume, _), .crossfade(let source, let volume, _):
            start(source: source, volume: volume)
        case .setVolume(let volume, _):
            setVolume(volume, target: parse(state.source ?? ""))
            state.volume = volume
        case .stop:
            mediaRemote.pause()
            state = .silent
        }
    }

    // MARK: Transitions

    private func start(source: String, volume: Double) {
        let target = parse(source)
        switch target {
        case .generic:
            mediaRemote.play()
        case .appleMusic(let playlist):
            if let playlist {
                AppleScriptRunner.run(#"""
                tell application "Music"
                    play playlist "\#(escape(playlist))"
                end tell
                """#)
            } else {
                AppleScriptRunner.run(#"tell application "Music" to play"#)
            }
        case .spotify(let playlist):
            if let playlist {
                AppleScriptRunner.run(#"""
                tell application "Spotify"
                    play track "\#(escape(playlist))"
                end tell
                """#)
            } else {
                AppleScriptRunner.run(#"tell application "Spotify" to play"#)
            }
        }
        setVolume(volume, target: target)
        state = AudioState(source: source, volume: volume, playing: true)
    }

    private func setVolume(_ volume: Double, target: Target) {
        let percent = Int((max(0, min(1, volume)) * 100).rounded())
        switch target {
        case .generic:
            break   // no addressable app to set a baseline on
        case .appleMusic:
            AppleScriptRunner.run(#"tell application "Music" to set sound volume to \#(percent)"#)
        case .spotify:
            AppleScriptRunner.run(#"tell application "Spotify" to set sound volume to \#(percent)"#)
        }
    }

    // MARK: Source parsing

    private func parse(_ source: String) -> Target {
        let parts = source.split(separator: ":", maxSplits: 3).map(String.init)
        // ["external", "command"]  or  ["external", "appleMusic"|"spotify", "playlist"|"command", id?]
        guard parts.count >= 2 else { return .generic }
        if parts[1] == "command" { return .generic }
        let playlist: String? = (parts.count >= 4 && parts[2] == "playlist") ? parts[3] : nil
        switch parts[1] {
        case "appleMusic": return .appleMusic(playlist: playlist)
        case "spotify": return .spotify(playlist: playlist)
        default: return .generic
        }
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
