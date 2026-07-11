import Foundation
import AppKit
import FadeoCore

/// Conducts a player you already use, rather than playing audio itself. Three layers:
/// - Generic transport (works for whichever app currently holds Now Playing, without
///   needing to know which one) via `MediaRemoteBridge`. No Automation permission needed.
/// - A pasted share link (`https://music.apple.com/...`, `https://open.spotify.com/...`)
///   is cued via AppleScript `open location`. Every alternative was tried against
///   ground truth and fails: `play playlist "<url>"` errors (-1700, a URL isn't a
///   playlist name), `NSWorkspace.open` with `activates=false, hides=true` is silently
///   DROPPED by Music, and an activating open steals focus (the original user-reported
///   bug). `open location` cues correctly with zero activation, even from cold launch.
/// - A local playlist **name** (Apple Music) or **URI** (`spotify:track:...`,
///   Spotify's AppleScript dictionary accepts URIs directly), via AppleScript.
///   Requires Automation access on first use; declining just means that targeting
///   silently no-ops, transport control still works.
///
/// **Threading**: `NSAppleScript` is synchronous, and talking to a cold-launching
/// Music.app can block for multiple seconds — so every AppleScript runs on a private
/// serial queue, never the main thread (this froze the UI before). `state` is only
/// touched on main.
///
/// **Verified playback**: a cold-launched player ignores commands until it's fully up,
/// and how long that takes varies by machine and moment — a fixed delay is wrong on
/// both sides. After a start, a bounded verify loop polls the player state and re-sends
/// `play` until it's actually playing (or ~12s passes). Each new command bumps a
/// generation counter that cancels any in-flight loop, so a stop or workspace switch
/// mid-verify never fights the new command. Bounded, event-initiated — not steady-state
/// polling.
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

        var appName: String? {
            switch self {
            case .generic: return nil
            case .appleMusic: return "Music"
            case .spotify: return "Spotify"
            }
        }

        var bundleID: String? {
            switch self {
            case .generic: return nil
            case .appleMusic: return "com.apple.Music"
            case .spotify: return "com.spotify.client"
            }
        }
    }

    private let mediaRemote = MediaRemoteBridge()
    private(set) var state: AudioState = .silent
    /// Fired (hopped to main) when a bounded verify loop gives up. Informational only —
    /// unlike InternalEngine, we never touch `state` here, since AppleScript read-back is
    /// unreliable by design (PLAN.md) and we don't want a false negative to desync it.
    var onPlaybackIssue: ((String) -> Void)?

    /// Serial: AppleScript calls are inherently ordered (launch → cue → play → volume),
    /// and this keeps them off the main thread.
    private let work = DispatchQueue(label: "fadeo.external", qos: .userInitiated)
    /// Bumped on every command; in-flight verify loops check it and bail when stale.
    /// Lock-protected: written on main (execute), read from the work queue mid-loop.
    private let genLock = NSLock()
    private var generation = 0

    private func bumpGeneration() -> Int {
        genLock.lock(); defer { genLock.unlock() }
        generation += 1
        return generation
    }

    private func isCurrent(_ gen: Int) -> Bool {
        genLock.lock(); defer { genLock.unlock() }
        return generation == gen
    }

    // MARK: Command execution (called on main)

    func execute(_ command: AudioCommand, order: PlaybackOrder = .sequential, repeatMode: RepeatMode = .all) {
        let gen = bumpGeneration()
        switch command {
        case .none:
            break
        case .start(let source, let volume, _), .crossfade(let source, let volume, _):
            state = AudioState(source: source, volume: volume, playing: true)
            let target = parse(source)
            work.async { [weak self] in self?.performStart(target: target, volume: volume, order: order, repeatMode: repeatMode, generation: gen) }
        case .setVolume(let volume, _):
            state.volume = volume
            let target = parse(state.source ?? "")
            work.async { [weak self] in self?.performSetVolume(volume, target: target) }
        case .pause:
            // Same underlying action as `.stop` (Music/Spotify only ever get paused, never
            // torn down here — see performStop's doc comment), but keep the source so a
            // `.resume` for the SAME source can tell it's continuing, not starting fresh.
            let target = parse(state.source ?? "")
            state = AudioState(source: state.source, volume: state.volume, playing: false, paused: true)
            work.async { [weak self] in self?.performStop(target: target) }
        case .resume(let volume, _):
            // Never re-cue: Music/Spotify already remember exactly where they paused, so
            // resuming just needs a bare `play`, not the whole open-location/verify dance.
            state = AudioState(source: state.source, volume: volume, playing: true, paused: false)
            let target = parse(state.source ?? "")
            work.async { [weak self] in self?.performResume(target: target, volume: volume) }
        case .stop:
            // Capture which app we were conducting BEFORE clearing state.
            let target = parse(state.source ?? "")
            state = .silent
            work.async { [weak self] in self?.performStop(target: target) }
        }
    }

    // MARK: Stop (background queue)

    /// Pause the SPECIFIC app we were conducting, not whatever generically holds Now
    /// Playing. The start path is app-specific (`tell Music to play`), so the stop must
    /// be too — the generic `MRMediaRemoteSendCommand(pause)` targets an ambiguous
    /// now-playing session that may not be Music/Spotify at all (and was verified
    /// unreliable in practice: Apple Music kept playing through a meeting override).
    /// Only script an app that's actually running, so pausing never *launches* it.
    private func performStop(target: Target) {
        switch target {
        case .appleMusic:
            if isRunning("com.apple.Music") {
                AppleScriptRunner.run(#"tell application "Music" to pause"#)
            } else {
                mediaRemote.pause()
            }
        case .spotify:
            if isRunning("com.spotify.client") {
                AppleScriptRunner.run(#"tell application "Spotify" to pause"#)
            } else {
                mediaRemote.pause()
            }
        case .generic:
            mediaRemote.pause()
        }
    }

    private func isRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// Manual "skip forward" (menu bar control) — generic transport, whichever app
    /// currently holds Now Playing.
    func next() { mediaRemote.next() }

    /// Resume from a `pause()`, never re-cueing (no `open location`, no verify loop) —
    /// Music/Spotify already hold the exact paused position, so a bare `play` continues
    /// it. Only launches the app if it's still running from the pause (never headless-
    /// launches here; if it quit in the meantime there's nothing to resume into).
    private func performResume(target: Target, volume: Double) {
        switch target {
        case .appleMusic:
            if isRunning("com.apple.Music") {
                AppleScriptRunner.run(#"tell application "Music" to play"#)
            } else {
                mediaRemote.play()
            }
        case .spotify:
            if isRunning("com.spotify.client") {
                AppleScriptRunner.run(#"tell application "Spotify" to play"#)
            } else {
                mediaRemote.play()
            }
        case .generic:
            mediaRemote.play()
        }
        performSetVolume(volume, target: target)
    }

    // MARK: Start (background queue)

    private func performStart(target: Target, volume: Double, order: PlaybackOrder, repeatMode: RepeatMode, generation gen: Int) {
        switch target {
        case .generic:
            mediaRemote.play()

        case .appleMusic(let playlist), .spotify(let playlist):
            guard let appName = target.appName, let bundleID = target.bundleID else { return }
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else {
                // The target app isn't installed. Fall back to opening the share link in
                // the default browser — this is promised in the Sound Library UI, and
                // without it we'd otherwise burn ~30s waiting on `waitUntilScriptable`/
                // `verifyPlaying` for an app that will never answer, before finally
                // reporting a failure. A local playlist name (no URL) has no browser
                // fallback — there's nothing to open.
                if let playlist, let url = shareLinkURL(playlist) {
                    DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                } else {
                    let issue = onPlaybackIssue
                    DispatchQueue.main.async { issue?("\(appName) isn't installed") }
                }
                return
            }
            launchHeadlessAndWait(bundleID: bundleID)
            guard isCurrent(gen) else { return }

            // A just-launched app accepts Apple Events before it can actually act on
            // them: an `open location` sent during initialization returns success and
            // is silently dropped (verified live — the volume command later in this
            // very flow succeeded while the cue evaporated). Wait until the app answers
            // a real query before cueing anything.
            waitUntilScriptable(appName: appName, generation: gen)
            guard isCurrent(gen) else { return }

            // The command that cues this source, re-sendable if a round gets dropped.
            let cue: String?
            if let playlist, let url = shareLinkURL(playlist) {
                // AppleScript `open location`, NOT NSWorkspace.open: verified against
                // ground truth that Music silently DROPS a share link delivered via
                // NSWorkspace with activates=false/hides=true, while an activating open
                // steals focus (the original bug). `open location` cues the link with
                // no activation at all. Spotify prefers its URI form.
                let location = (appName == "Spotify") ? spotifyLocation(url) : url.absoluteString
                cue = #"tell application "\#(appName)" to open location "\#(escape(location))""#
            } else if let playlist {
                if case .appleMusic = target {
                    cue = #"tell application "Music" to play playlist "\#(escape(playlist))""#
                } else {
                    cue = #"tell application "Spotify" to play track "\#(escape(playlist))""#
                }
            } else {
                cue = nil
            }

            if let cue { AppleScriptRunner.run(cue) }
            verifyPlaying(appName: appName, cue: cue, generation: gen)
            guard isCurrent(gen) else { return }
            // Shuffle/repeat only stick once something is actually playing — an empty
            // queue can't shuffle — so set them AFTER playback is confirmed, not before.
            //
            // A single pasted song forces repeat-one regardless of the workspace's
            // configured repeatMode: neither Music nor Spotify exposes an AppleScript
            // property to disable their own "Autoplay"/"Radio" continuation (checked
            // Music's AppleScript dictionary directly — no such property exists), so
            // repeat-off on a single-song "queue" lets the app fill in with an unrelated
            // song once it ends. Looping the same song is the only way to get defined,
            // repeatable behavior out of a single share link.
            let effectiveRepeat = isSingleTrackLink(target: target, playlist: playlist) ? RepeatMode.one : repeatMode
            applyShuffleRepeat(appName: appName, order: order, repeatMode: effectiveRepeat)
            performSetVolume(volume, target: target)
        }
    }

    /// Configure the external app's own shuffle/repeat to match the workspace, so e.g.
    /// "Deep Work → Apple Music, shuffled, repeat all" actually shuffles Music. Music
    /// and Spotify expose different AppleScript vocabularies for this. (These setters
    /// only take effect during active playback, hence the ordering above.)
    private func applyShuffleRepeat(appName: String, order: PlaybackOrder, repeatMode: RepeatMode) {
        if appName == "Music" {
            AppleScriptRunner.run(#"tell application "Music" to set shuffle enabled to \#(order == .shuffle)"#)
            let mode = { switch repeatMode { case .off: return "off"; case .one: return "one"; case .all: return "all" } }()
            AppleScriptRunner.run(#"tell application "Music" to set song repeat to \#(mode)"#)
        } else {
            AppleScriptRunner.run(#"tell application "Spotify" to set shuffling to \#(order == .shuffle)"#)
            // Spotify's AppleScript repeat is a single on/off (loop the context); map
            // both "one" and "all" to on, "off" to off.
            AppleScriptRunner.run(#"tell application "Spotify" to set repeating to \#(repeatMode != .off)"#)
        }
    }

    /// Spotify's AppleScript handles `spotify:` URIs more reliably than https share
    /// links: convert `https://open.spotify.com/track/<id>?...` → `spotify:track:<id>`.
    /// Links that don't fit the pattern pass through unchanged.
    private func spotifyLocation(_ url: URL) -> String {
        let parts = url.path.split(separator: "/").map(String.init)
        guard url.host?.contains("spotify.com") == true, parts.count >= 2 else { return url.absoluteString }
        let kind = parts[parts.count - 2]
        let id = parts[parts.count - 1]
        guard ["track", "album", "playlist", "artist", "episode", "show"].contains(kind) else { return url.absoluteString }
        return "spotify:\(kind):\(id)"
    }

    /// Block (on the work queue) until the app answers an Apple Event query — the
    /// signal that it's finished initializing and will honor real commands.
    private func waitUntilScriptable(appName: String, generation gen: Int) {
        for _ in 0..<25 {   // × 400ms = 10s ceiling
            guard isCurrent(gen) else { return }
            if playerState(appName: appName) != nil { return }
            Thread.sleep(forTimeInterval: 0.4)
        }
    }

    /// Poll the player state until it's actually playing or the budget runs out.
    /// `paused` gets a `play` nudge (a cued share link does not auto-start, and `play`
    /// is ignored while the catalog item is still resolving — hence repeated gentle
    /// nudges, verified live). `stopped` means the cue itself was dropped — but
    /// re-cueing every round restarts catalog resolution and thrashes, so the cue is
    /// re-sent only twice, well spaced.
    private func verifyPlaying(appName: String, cue: String?, generation gen: Int) {
        let maxAttempts = 30          // × 700ms ≈ 21s ceiling (cold launch + catalog resolution)
        for attempt in 0..<maxAttempts {
            guard isCurrent(gen) else { return }
            let state = playerState(appName: appName)
            if state == "playing" { return }
            if state == "stopped" {
                // Give resolution time; only assume the cue was lost after real waits.
                if (attempt == 6 || attempt == 14), let cue {
                    AppleScriptRunner.run(cue)
                }
            } else if attempt >= 2 {
                AppleScriptRunner.run(#"tell application "\#(appName)" to play"#)
            }
            Thread.sleep(forTimeInterval: 0.7)
        }
        NSLog("Fadeo ExternalConductor: \(appName) did not reach playing state in time")
        let issue = onPlaybackIssue
        DispatchQueue.main.async { issue?("\(appName) did not start playing") }
    }

    private func playerState(appName: String) -> String? {
        AppleScriptRunner.runReturningString(#"tell application "\#(appName)" to player state as string"#)
    }

    private func performSetVolume(_ volume: Double, target: Target) {
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

    // MARK: Launch / handoff plumbing (background queue)

    /// Apple Events sent to a not-yet-running regular app trigger Launch Services'
    /// default foreground launch, which is why bare `tell application "Music" to play`
    /// steals focus the first time. Claiming the launch ourselves with `activates =
    /// false, hides = true` beforehand means the app launches hidden in the background,
    /// and later Apple Events just talk to that instance. Blocks (briefly, on the work
    /// queue) until the launch callback fires so follow-up commands have a live target.
    private func launchHeadlessAndWait(bundleID: String) {
        guard NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) == nil else { return }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error { NSLog("Fadeo: headless launch of \(bundleID) failed: \(error)") }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 8)
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

    /// True when `playlist` names one specific song rather than an album/playlist (a
    /// real queue, where looping doesn't make sense). Music share links for an individual
    /// track carry an `i=<trackId>` query parameter; a bare album/playlist link doesn't.
    /// Spotify: a `/track/` path segment or a `spotify:track:` URI.
    private func isSingleTrackLink(target: Target, playlist: String?) -> Bool {
        guard let playlist else { return false }
        if let url = shareLinkURL(playlist) {
            switch target {
            case .appleMusic:
                return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.contains(where: { $0.name == "i" }) ?? false
            case .spotify:
                return url.path.split(separator: "/").map(String.init).contains("track")
            case .generic:
                return false
            }
        }
        if case .spotify = target { return playlist.hasPrefix("spotify:track:") }
        return false
    }
}
