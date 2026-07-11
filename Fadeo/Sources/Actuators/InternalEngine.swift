import Foundation
import AVFoundation
import FadeoCore

/// Fadeo's self-contained player. Two independent playback paths share one
/// `AVAudioEngine`, mutually exclusive at any moment (Fadeo plays one thing at a time):
///
/// - **Ambient presets** (`internal:preset:*`) are *synthesized* in a real-time render
///   block (brown/pink/white noise). No shipped audio files, seamless, tiny footprint.
/// - **Your own audio** (`internal:file:<path>`, `internal:folder:<path>`,
///   `internal:playlist:<id>`) is played via `AVAudioPlayerNode`, queued and ordered per
///   the workspace's `order`/`repeatMode`. This is the "bring your own sound" pillar.
///
/// Fades are sample-accurate for the noise path and a short bounded timer-driven ramp for
/// the file path (AVAudioMixerNode has no ramping API of its own). The engine is fully
/// stopped when idle so it drops to ~0% CPU and releases the audio hardware.
final class InternalEngine {

    private enum SourceKind: Equatable { case preset, files }

    private let engine = AVAudioEngine()
    private let sampleRate: Double = 48_000
    private var format: AVAudioFormat?

    // Noise path
    private let renderer = NoiseRenderer()
    private var noiseNode: AVAudioSourceNode?
    private var noiseConfigured = false

    // File path
    private var playerNode: AVAudioPlayerNode?
    private let fileMixer = AVAudioMixerNode()
    private var fileConfigured = false
    /// The format the player→mixer connection was last made with; reconnected whenever
    /// the next track's processing format differs (see playCurrentQueueItem).
    private var fileConnectionFormat: AVAudioFormat?
    private var queue: [URL] = []
    private var queueIndex = 0
    private var order: PlaybackOrder = .sequential
    private var repeatMode: RepeatMode = .all
    private var fadeTimer: DispatchSourceTimer?
    /// Guards against a completion handler from a *stale* schedule (e.g. after a stop or
    /// a switch to a different source) advancing a queue that's no longer current.
    private var playbackGeneration = 0

    private var localPlaylists: [LocalPlaylist] = []
    private var activeKind: SourceKind?

    /// Scheduled work for the second half of a crossfade / the end of a fade-out.
    private var pendingWork: DispatchWorkItem?

    private(set) var state: AudioState = .silent

    private static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "alac", "caf",
    ]

    /// The app calls this whenever config reloads so folder/playlist sources always
    /// resolve against the current definitions.
    func updateLocalPlaylists(_ playlists: [LocalPlaylist]) {
        localPlaylists = playlists
    }

    // MARK: Command execution (called on main from the AppController)

    func execute(_ command: AudioCommand, order: PlaybackOrder = .sequential, repeatMode: RepeatMode = .all) {
        self.order = order
        self.repeatMode = repeatMode
        switch command {
        case .none:
            break
        case .start(let source, let volume, let fadeMs):
            start(source: source, volume: volume, fadeMs: fadeMs)
        case .crossfade(let source, let volume, let ms):
            crossfade(to: source, volume: volume, ms: ms)
        case .setVolume(let volume, let ms):
            setVolume(volume, ms: ms)
        case .stop(let fadeMs):
            stop(fadeMs: fadeMs)
        }
    }

    // MARK: Transitions

    private func start(source: String, volume: Double, fadeMs: Int) {
        pendingWork?.cancel(); pendingWork = nil
        let kind = sourceKind(source)

        switch kind {
        case .preset:
            stopFilePlaybackImmediate()
            configureNoiseIfNeeded()
            startEngineIfNeeded()
            renderer.kind = NoiseRenderer.Kind(source: source)
            renderer.setRamp(to: calibratedGain(volume, source: source), ms: fadeMs, sampleRate: sampleRate)
            activeKind = .preset
            state = AudioState(source: source, volume: volume, playing: true)

        case .files:
            silenceNoiseImmediate()
            let urls = resolveQueue(source)
            guard !urls.isEmpty else {
                NSLog("Fadeo InternalEngine: no playable files for source \(source)")
                activeKind = nil
                state = .silent
                return
            }
            queue = order == .shuffle ? urls.shuffled() : urls
            queueIndex = 0
            configureFileIfNeeded()
            startEngineIfNeeded()
            activeKind = .files
            state = AudioState(source: source, volume: volume, playing: true)
            playCurrentQueueItem(fadeInMs: fadeMs)
        }
    }

    private func crossfade(to source: String, volume: Double, ms: Int) {
        pendingWork?.cancel()
        // Invalidate any in-flight natural track-advance now, not when the delayed swap
        // fires. Otherwise a track finishing during the fade-out window snaps the volume
        // back to full, fighting the fade. See git history for how this was caught.
        playbackGeneration += 1
        let half = max(1, ms / 2)

        switch activeKind {
        case .preset: renderer.setRamp(to: 0, ms: half, sampleRate: sampleRate)
        case .files:  rampFileVolume(to: 0, ms: half)
        case nil:     break
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.silenceNoiseImmediate()
            self.stopFilePlaybackImmediate()
            self.start(source: source, volume: volume, fadeMs: half)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(half), execute: work)
    }

    private func setVolume(_ volume: Double, ms: Int) {
        switch activeKind {
        case .preset:
            renderer.setRamp(to: calibratedGain(volume, source: state.source ?? ""), ms: ms, sampleRate: sampleRate)
        case .files:
            rampFileVolume(to: Float(volume), ms: ms)
        case nil:
            break
        }
        state.volume = volume
    }

    private func stop(fadeMs: Int) {
        pendingWork?.cancel()
        playbackGeneration += 1   // same reasoning as crossfade above
        switch activeKind {
        case .preset: renderer.setRamp(to: 0, ms: fadeMs, sampleRate: sampleRate)
        case .files:  rampFileVolume(to: 0, ms: fadeMs)
        case nil:     break
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.playerNode?.stop()
            self.playbackGeneration += 1
            self.engine.stop()               // release the audio HAL → ~0% CPU when idle
            self.activeKind = nil
            self.state = .silent
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(0, fadeMs)), execute: work)
    }

    // MARK: File queue playback

    /// `attemptsLeft` bounds how many consecutive unplayable files we'll skip before
    /// giving up — without it, a queue where the current (or only) file can't be opened
    /// recurses forever: `(i+1) % count` wraps back to the same bad file and retries
    /// endlessly, overflowing the stack. Defaults to one full pass over the queue.
    private func playCurrentQueueItem(fadeInMs: Int, attemptsLeft: Int? = nil) {
        guard let node = playerNode, queue.indices.contains(queueIndex) else { return }
        let budget = attemptsLeft ?? queue.count
        let url = queue[queueIndex]
        guard let file = try? AVAudioFile(forReading: url) else {
            NSLog("Fadeo InternalEngine: could not open \(url.lastPathComponent), skipping")
            advancePastUnplayable(attemptsLeft: budget - 1)
            return
        }
        // AVAudioPlayerNode does NOT sample-rate-convert: the player→mixer connection
        // format must match the file's own processing format, or playback is silent /
        // wrong-speed (a 44.1kHz mp3 through the engine's 48kHz graph — i.e. almost
        // every real-world file). Reconnect per track when the format changes; the
        // mixer's output side handles conversion to the engine rate from there.
        if fileConnectionFormat != file.processingFormat {
            node.stop()
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: fileMixer, format: file.processingFormat)
            fileConnectionFormat = file.processingFormat
        }
        playbackGeneration += 1
        let generation = playbackGeneration
        node.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                self?.handleTrackFinished(generation: generation)
            }
        }
        if !node.isPlaying { node.play() }
        // Read state.volume live (not a value captured earlier in the completion chain) so
        // a setVolume that happened mid-track is respected on the next auto-advance.
        rampFileVolume(to: Float(state.volume), ms: fadeInMs)
    }

    private func advancePastUnplayable(attemptsLeft: Int) {
        guard !queue.isEmpty, attemptsLeft > 0 else {
            NSLog("Fadeo InternalEngine: no playable files in the source, going silent")
            playerNode?.stop()
            fileMixer.outputVolume = 0
            activeKind = nil
            state = .silent
            return
        }
        queueIndex = (queueIndex + 1) % queue.count
        playCurrentQueueItem(fadeInMs: 0, attemptsLeft: attemptsLeft)
    }

    private func handleTrackFinished(generation: Int) {
        // A stop/crossfade already invalidated this schedule (bumped playbackGeneration
        // the instant it was requested, not when it completes). Do nothing, so a track
        // finishing mid-fade-out never snaps the volume back up.
        guard generation == playbackGeneration, activeKind == .files else { return }
        switch repeatMode {
        case .one:
            break   // replay the same index
        case .all:
            queueIndex = (queueIndex + 1) % queue.count
        case .off:
            queueIndex += 1
            guard queue.indices.contains(queueIndex) else {
                activeKind = nil
                state = .silent
                return
            }
        }
        playCurrentQueueItem(fadeInMs: 0)
    }

    // MARK: Volume ramp (file path: AVAudioMixerNode has no built-in ramping)

    private func rampFileVolume(to target: Float, ms: Int) {
        fadeTimer?.cancel(); fadeTimer = nil
        guard ms > 0 else { fileMixer.outputVolume = target; return }
        let start = fileMixer.outputVolume
        let stepMs = 16
        let steps = max(1, ms / stepMs)
        var step = 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(stepMs), repeating: .milliseconds(stepMs))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            step += 1
            if step >= steps {
                self.fileMixer.outputVolume = target
                self.fadeTimer?.cancel(); self.fadeTimer = nil
            } else {
                self.fileMixer.outputVolume = start + (target - start) * Float(step) / Float(steps)
            }
        }
        fadeTimer = timer
        timer.resume()
    }

    // MARK: Source resolution (pure-ish; touches the filesystem, stays app-side by design)

    private func sourceKind(_ source: String) -> SourceKind {
        source.hasPrefix("internal:preset:") ? .preset : .files
    }

    private func resolveQueue(_ source: String) -> [URL] {
        let parts = source.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "internal" else { return [] }
        switch parts[1] {
        case "file":
            let url = URL(fileURLWithPath: parts[2])
            return FileManager.default.fileExists(atPath: url.path) ? [url] : []
        case "folder":
            return filesInFolder(parts[2])
        case "playlist":
            return filesInPlaylist(parts[2])
        default:
            return []
        }
    }

    private func filesInFolder(_ path: String) -> [URL] {
        let url = URL(fileURLWithPath: path)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return items
            .filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func filesInPlaylist(_ id: String) -> [URL] {
        guard let playlist = localPlaylists.first(where: { $0.id == id }) else { return [] }
        return playlist.paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Perceptual calibration so equal baseline numbers sound equally loud across noise
    /// textures (white reads far louder than brown at the same RMS). Does NOT include the
    /// system volume — the hardware applies that (PLAN.md 6a). Not applied to user files:
    /// they're pre-mastered content, not our synthesized noise.
    private func calibratedGain(_ volume: Double, source: String) -> Float {
        let cal: Float
        switch NoiseRenderer.Kind(source: source) {
        case .brown: cal = 1.0
        case .pink:  cal = 0.85
        case .white: cal = 0.5
        case .rain:  cal = 0.75
        case .ocean: cal = 0.95
        case .wind:  cal = 0.8
        case .fan:   cal = 0.9
        }
        return Float(volume) * cal
    }

    // MARK: Engine setup

    private func sharedFormat() -> AVAudioFormat {
        if let format { return format }
        let f = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        format = f
        return f
    }

    private func configureNoiseIfNeeded() {
        guard !noiseConfigured else { return }
        let fmt = sharedFormat()
        let node = AVAudioSourceNode(format: fmt) { [renderer] _, _, frameCount, ablPtr in
            let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
            renderer.render(frameCount: Int(frameCount), abl: abl)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        noiseNode = node
        noiseConfigured = true
    }

    private func configureFileIfNeeded() {
        guard !fileConfigured else { return }
        let fmt = sharedFormat()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.attach(fileMixer)
        // The player→mixer leg is (re)connected per track with the file's own format —
        // see playCurrentQueueItem. Only the mixer→main leg is fixed at the engine rate;
        // AVAudioMixerNode converts between its inputs and its output format.
        engine.connect(fileMixer, to: engine.mainMixerNode, format: fmt)
        playerNode = node
        fileConfigured = true
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("Fadeo InternalEngine: engine start failed: \(error.localizedDescription)")
        }
    }

    private func silenceNoiseImmediate() {
        guard noiseConfigured else { return }
        renderer.setRamp(to: 0, ms: 0, sampleRate: sampleRate)
    }

    private func stopFilePlaybackImmediate() {
        fadeTimer?.cancel(); fadeTimer = nil
        playbackGeneration += 1
        playerNode?.stop()
        fileMixer.outputVolume = 0
    }
}

// MARK: - Real-time noise renderer

/// Holds all DSP state and the fade envelope. Lives independently of the engine wrapper so
/// the render block captures only this (no retain cycle back to `InternalEngine`).
/// Control-thread writes to the gain/kind fields race benignly with the audio thread —
/// worst case is a one-sample discontinuity, never a crash.
private final class NoiseRenderer {
    enum Kind: Int {
        case brown, pink, white, rain, ocean, wind, fan
        init(source: String) {
            if source.contains("white") { self = .white }
            else if source.contains("pink") { self = .pink }
            else if source.contains("rain") { self = .rain }
            else if source.contains("ocean") { self = .ocean }
            else if source.contains("wind") { self = .wind }
            else if source.contains("fan") { self = .fan }
            else { self = .brown }   // brown-noise and default
        }
    }

    var kind: Kind = .brown
    var sampleRate: Double = 48_000

    // Fade envelope (per-sample ramp)
    private var currentGain: Float = 0
    private var targetGain: Float = 0
    private var gainStep: Float = 0

    // Core noise state (audio thread)
    private var rng: UInt32 = 0x9E37_79B9
    private var brownLast: Float = 0
    private var p0: Float = 0, p1: Float = 0, p2: Float = 0, p3: Float = 0
    private var p4: Float = 0, p5: Float = 0, p6: Float = 0

    // Texture DSP state
    private var lpA: Float = 0, lpB: Float = 0        // cascaded one-pole low-pass (ocean/fan)
    private var hpLast: Float = 0, hpPrev: Float = 0  // one-pole high-pass (rain brightness)
    private var svLow: Float = 0, svBand: Float = 0   // state-variable bandpass (wind)
    private var oceanPhase: Float = 0                 // wave swell LFO
    private var gustPhase: Float = 0                  // wind gust LFO
    private var humPhase: Float = 0                   // fan tonal hum
    private var dropEnv: Float = 0                    // rain droplet decay
    private var dropPhase: Float = 0, dropInc: Float = 0

    private let headroom: Float = 0.38   // keep well below clipping

    func setRamp(to value: Float, ms: Int, sampleRate: Double) {
        self.sampleRate = sampleRate
        targetGain = value
        if ms <= 0 {
            currentGain = value
            gainStep = 0
        } else {
            let samples = Float(Double(ms) / 1000.0 * sampleRate)
            gainStep = (value - currentGain) / max(1, samples)
        }
    }

    func render(frameCount: Int, abl: UnsafeMutableAudioBufferListPointer) {
        // Standard format: float32, non-interleaved, one buffer per channel.
        for frame in 0..<frameCount {
            stepGain()
            let sample = nextSample() * headroom * currentGain
            for buffer in abl {
                if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                    data[frame] = sample
                }
            }
        }
    }

    private func stepGain() {
        guard gainStep != 0 else { return }
        currentGain += gainStep
        if (gainStep > 0 && currentGain >= targetGain) || (gainStep < 0 && currentGain <= targetGain) {
            currentGain = targetGain
            gainStep = 0
        }
    }

    private func nextSample() -> Float {
        let white = nextWhite()
        switch kind {
        case .white:
            return white
        case .brown:
            return brown(white) * 3.5
        case .pink:
            return pink(white)
        case .rain:
            // Bright, band-limited hiss (high-passed pink) plus sparse decaying droplets.
            let base = highPass(pink(white)) * 1.4
            if dropEnv < 0.001, nextUnit() < 0.0012 {           // ~58 drops/sec at 48k
                dropEnv = 0.6 + 0.4 * nextUnit()
                dropInc = (2500 + 3500 * nextUnit()) * 2 * .pi / Float(sampleRate)
                dropPhase = 0
            }
            var drop: Float = 0
            if dropEnv > 0.001 {
                drop = sin(dropPhase) * dropEnv
                dropPhase += dropInc
                dropEnv *= 0.992                                 // fast decay = a "tick"
            }
            return base * 0.7 + drop * 0.5
        case .ocean:
            // Slow swell: low-passed brown modulated by a ~0.09 Hz wave envelope.
            let wash = lowPass(brown(white) * 3.5)
            oceanPhase += 2 * .pi * 0.09 / Float(sampleRate)
            if oceanPhase > 2 * .pi { oceanPhase -= 2 * .pi }
            let swell = 0.28 + 0.72 * (0.5 + 0.5 * sin(oceanPhase))
            return wash * swell * 1.7
        case .wind:
            // Resonant band-passed white with a gusting amplitude (~0.14 Hz).
            let band = bandPass(white)
            gustPhase += 2 * .pi * 0.14 / Float(sampleRate)
            if gustPhase > 2 * .pi { gustPhase -= 2 * .pi }
            let gust = 0.25 + 0.75 * (0.5 + 0.5 * sin(gustPhase))
            return band * gust * 2.2
        case .fan:
            // Steady low-passed hiss plus a faint tonal hum, like an AC unit or box fan.
            let air = lowPass(white) * 1.6
            humPhase += 2 * .pi * 110 / Float(sampleRate)
            if humPhase > 2 * .pi { humPhase -= 2 * .pi }
            let hum = sin(humPhase) * 0.12
            return air * 0.9 + hum
        }
    }

    // MARK: DSP primitives (all one-liners of persistent state; real-time safe)

    private func brown(_ white: Float) -> Float {
        brownLast = (brownLast + 0.02 * white) / 1.02
        return brownLast
    }

    private func pink(_ white: Float) -> Float {
        // Paul Kellet's economy pink-noise filter.
        p0 = 0.99886 * p0 + white * 0.0555179
        p1 = 0.99332 * p1 + white * 0.0750759
        p2 = 0.96900 * p2 + white * 0.1538520
        p3 = 0.86650 * p3 + white * 0.3104856
        p4 = 0.55000 * p4 + white * 0.5329522
        p5 = -0.7616 * p5 - white * 0.0168980
        let out = p0 + p1 + p2 + p3 + p4 + p5 + p6 + white * 0.5362
        p6 = white * 0.115926
        return out * 0.5
    }

    /// Two cascaded one-pole low-passes (~gentle roll-off, warms/darkens).
    private func lowPass(_ x: Float) -> Float {
        lpA += 0.08 * (x - lpA)
        lpB += 0.08 * (lpA - lpB)
        return lpB
    }

    /// One-pole high-pass (brightens — removes the low rumble for rain hiss).
    private func highPass(_ x: Float) -> Float {
        let y = 0.92 * (hpPrev + x - hpLast)
        hpLast = x
        hpPrev = y
        return y
    }

    /// State-variable bandpass centered ~500 Hz, moderate Q — the whistle of wind.
    private func bandPass(_ x: Float) -> Float {
        let f: Float = 2 * sin(.pi * 500 / Float(sampleRate))
        let q: Float = 0.4
        svLow += f * svBand
        let high = x - svLow - q * svBand
        svBand += f * high
        return svBand
    }

    /// Fast xorshift PRNG → white noise in [-1, 1]. Real-time safe (no allocation/locks).
    private func nextWhite() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(Int32(bitPattern: rng)) / Float(Int32.max)
    }

    /// Uniform in [0, 1).
    private func nextUnit() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(rng) / Float(UInt32.max)
    }
}
