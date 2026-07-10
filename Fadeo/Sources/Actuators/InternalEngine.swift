import Foundation
import AVFoundation
import FadeoCore

/// Fadeo's self-contained player. For the ambient starter set we *synthesize* the sound
/// in a real-time render block (brown/pink/white noise) — no shipped audio files, tiny
/// footprint, and infinite length with no looping seams. Local files & external players
/// come later (M2). Fades are sample-accurate; the engine is fully stopped when idle so
/// it drops to ~0% CPU and releases the audio hardware.
final class InternalEngine {

    private let engine = AVAudioEngine()
    private let renderer = NoiseRenderer()
    private var sourceNode: AVAudioSourceNode?
    private let sampleRate: Double = 48_000
    private var configured = false

    /// Scheduled work for the second half of a crossfade / the end of a fade-out.
    private var pendingWork: DispatchWorkItem?

    private(set) var state: AudioState = .silent

    // MARK: Command execution (called on main from the AppController)

    func execute(_ command: AudioCommand) {
        switch command {
        case .none:
            break
        case .start(let source, let volume, let fadeMs):
            start(source: source, volume: volume, fadeMs: fadeMs)
        case .crossfade(let source, let volume, let ms):
            crossfade(to: source, volume: volume, ms: ms)
        case .setVolume(let volume, let ms):
            renderer.setRamp(to: Float(volume), ms: ms, sampleRate: sampleRate)
            state.volume = volume
        case .stop(let fadeMs):
            stop(fadeMs: fadeMs)
        }
    }

    // MARK: Transitions

    private func start(source: String, volume: Double, fadeMs: Int) {
        pendingWork?.cancel(); pendingWork = nil
        renderer.kind = NoiseRenderer.Kind(source: source)
        configureIfNeeded()
        startEngineIfNeeded()
        renderer.setRamp(to: Float(volume), ms: fadeMs, sampleRate: sampleRate)
        state = AudioState(source: source, volume: volume, playing: true)
    }

    private func crossfade(to source: String, volume: Double, ms: Int) {
        pendingWork?.cancel()
        let half = max(1, ms / 2)
        // Fade the outgoing texture down…
        renderer.setRamp(to: 0, ms: half, sampleRate: sampleRate)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // …swap texture at the trough, fade the incoming one up.
            self.renderer.kind = NoiseRenderer.Kind(source: source)
            self.renderer.setRamp(to: Float(volume), ms: half, sampleRate: self.sampleRate)
            self.state = AudioState(source: source, volume: volume, playing: true)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(half), execute: work)
    }

    private func stop(fadeMs: Int) {
        pendingWork?.cancel()
        renderer.setRamp(to: 0, ms: fadeMs, sampleRate: sampleRate)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.engine.stop()               // release the audio HAL → ~0% CPU when idle
            self.state = .silent
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(0, fadeMs)), execute: work)
    }

    // MARK: Engine setup

    private func configureIfNeeded() {
        guard !configured else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        let node = AVAudioSourceNode(format: format) { [renderer] _, _, frameCount, ablPtr in
            let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
            renderer.render(frameCount: Int(frameCount), abl: abl)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
        configured = true
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
}

// MARK: - Real-time noise renderer

/// Holds all DSP state and the fade envelope. Lives independently of the engine wrapper so
/// the render block captures only this (no retain cycle back to `InternalEngine`).
/// Control-thread writes to the gain/kind fields race benignly with the audio thread —
/// worst case is a one-sample discontinuity, never a crash.
private final class NoiseRenderer {
    enum Kind: Int {
        case brown, pink, white
        init(source: String) {
            if source.contains("white") { self = .white }
            else if source.contains("pink") || source.contains("rain") { self = .pink }
            else { self = .brown }   // brown-noise and default
        }
    }

    var kind: Kind = .brown

    // Fade envelope (per-sample ramp)
    private var currentGain: Float = 0
    private var targetGain: Float = 0
    private var gainStep: Float = 0

    // DSP state (audio thread)
    private var rng: UInt32 = 0x9E37_79B9
    private var brownLast: Float = 0
    private var p0: Float = 0, p1: Float = 0, p2: Float = 0, p3: Float = 0
    private var p4: Float = 0, p5: Float = 0, p6: Float = 0

    private let headroom: Float = 0.38   // keep well below clipping

    func setRamp(to value: Float, ms: Int, sampleRate: Double) {
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
            brownLast = (brownLast + 0.02 * white) / 1.02
            return brownLast * 3.5
        case .pink:
            // Paul Kellet's economy pink-noise filter.
            p0 = 0.99886 * p0 + white * 0.0555179
            p1 = 0.99332 * p1 + white * 0.0750759
            p2 = 0.96900 * p2 + white * 0.1538520
            p3 = 0.86650 * p3 + white * 0.3104856
            p4 = 0.55000 * p4 + white * 0.5329522
            p5 = -0.7616 * p5 - white * 0.0168980
            let pink = p0 + p1 + p2 + p3 + p4 + p5 + p6 + white * 0.5362
            p6 = white * 0.115926
            return pink * 0.5
        }
    }

    /// Fast xorshift PRNG → white noise in [-1, 1]. Real-time safe (no allocation/locks).
    private func nextWhite() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(Int32(bitPattern: rng)) / Float(Int32.max)
    }
}
