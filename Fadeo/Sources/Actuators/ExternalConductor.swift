import Foundation
import AppKit
import FadeoCore

/// Conducts a player you already use, rather than playing audio itself. Three layers:
/// - Generic transport (works for whichever app currently holds Now Playing, without
///   needing to know which one) via `MediaRemoteBridge`. No Automation permission needed.
/// - A pasted share link (`https://music.apple.com/...`, `https://open.spotify.com/...`)
///   is handed to the target app via `NSWorkspace.open`, not AppleScript. There is no
///   AppleScript verb to "play this catalog URL" for either app, but both handle their
///   own share links directly (this is what happens when you click one anywhere else).
///   Verified against ground truth: `play playlist "<url>"` fails (-1700, a URL isn't a
///   playlist name); `open -a Music "<url>"` correctly starts playback.
/// - A local playlist **name** (Apple Music) or **URI** (`spotify:track:...`,
///   Spotify's AppleScript dictionary accepts URIs directly), via AppleScript.
///   Requires Automation access on first use; declining just means that targeting
///   silently no-ops, transport control still works.
///
/// Source grammar (see PLAN.md §4):
///   external:command                       play/pause whatever's currently cued, any app
///   external:appleMusic:command            same, explicitly through Music.app
///   external:appleMusic:playlist:<name>    switch Music.app to that local playlist
///   external:appleMusic:playlist:<url>     open a music.apple.com share link
///   external:spotify:command               same, explicitly through Spotify
///   external:spotify:playlist:<uri-or-url> a spotify: URI (AppleScript) or open.spotify.com link
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
            ensureRunningHeadless(bundleID: "com.apple.Music")
            if let playlist, let url = shareLinkURL(playlist) {
                openShareLink(url, bundleID: "com.apple.Music")
                playAfterHandoff(#"tell application "Music" to play"#)
            } else if let playlist {
                AppleScriptRunner.run(#"""
                tell application "Music"
                    play playlist "\#(escape(playlist))"
                end tell
                """#)
            } else {
                AppleScriptRunner.run(#"tell application "Music" to play"#)
            }
        case .spotify(let playlist):
            ensureRunningHeadless(bundleID: "com.spotify.client")
            if let playlist, let url = shareLinkURL(playlist) {
                openShareLink(url, bundleID: "com.spotify.client")
                playAfterHandoff(#"tell application "Spotify" to play"#)
            } else if let playlist {
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

    /// A pasted `https://` share link, as opposed to a local playlist name or a
    /// `spotify:` URI, both of which AppleScript handles directly.
    private func shareLinkURL(_ s: String) -> URL? {
        guard s.hasPrefix("http://") || s.hasPrefix("https://"), let url = URL(string: s) else { return nil }
        return url
    }

    /// Hand a share link to the specific app rather than relying on default URL-scheme
    /// resolution, which needs the extra nudge of a concrete target (see file header).
    private func openShareLink(_ url: URL, bundleID: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSWorkspace.shared.open(url)   // app not found by id, best effort via default handler
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
    }

    /// Apple Events sent to a not-yet-running regular app trigger Launch Services'
    /// default foreground launch, which is why bare `tell application "Music" to play`
    /// steals focus the first time. Claiming the launch ourselves with `activates =
    /// false, hides = true` beforehand means the app is already running (or launching
    /// hidden) by the time the AppleScript command reaches it, so the Apple Event just
    /// talks to that instance instead of triggering its own foregrounding launch.
    /// No-op if the app is already running — talking to a running app never changes
    /// its front/back state regardless of activation settings.
    private func ensureRunningHeadless(bundleID: String) {
        guard NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) == nil else { return }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                NSLog("Fadeo: headless launch of \(bundleID) failed: \(error)")
            }
        }
    }

    /// A share link loads/cues the right track but does NOT auto-start playback (verified
    /// against ground truth: player state stays "paused" until an explicit play follows).
    /// The app needs a moment to finish handling the handoff first, or an immediate `play`
    /// lands before there's anything to play.
    private func playAfterHandoff(_ script: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            AppleScriptRunner.run(script)
        }
    }
}
