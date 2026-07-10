import Foundation
import Combine
import FadeoCore

/// The M0 brain: sensors → Context → (debounced) resolve → Decision + trace.
/// Audio actuators land in M1; here we prove the whole event-driven pipeline and expose
/// live state for the dashboard and menu bar. No polling anywhere — every update is
/// driven by an OS push through a sensor.
@MainActor
final class AppController: ObservableObject {
    // Live state (published to the UI)
    @Published private(set) var context = Context()
    @Published private(set) var decision: Decision?
    @Published private(set) var recentEvents: [String] = []
    @Published private(set) var eventCount: Int = 0
    @Published private(set) var audioStatus: String = "silent"
    @Published var automationPaused = false {
        didSet {
            if automationPaused {
                engine.execute(.stop(fadeMs: configStore.config.settings.defaults.fadeOutMs))
                audioState = .silent
                updateAudioStatus()
            } else {
                evaluate()
            }
        }
    }

    let configStore: ConfigStore
    private let resolver = Resolver()
    private var resolverState = ResolverState()

    // Audio actuation
    private let engine = InternalEngine()
    private let reconciler = Reconciler()
    private var audioState: AudioState = .silent

    // Sensors (only AppFocus in M0; the rest slot in behind the same protocol at M3)
    private let appFocus = AppFocusSensor()

    // Debounce
    private var pendingEval: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    let startedAt = Date()

    init(configStore: ConfigStore) {
        self.configStore = configStore

        // Re-evaluate whenever the config hot-reloads.
        configStore.$config
            .dropFirst()
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)

        startSensors()
        evaluate()
    }

    var activeWorkspaceName: String? {
        guard let id = resolverState.activeWorkspace else { return nil }
        return configStore.config.workspaces.first { $0.id == id }?.name
    }

    var uptimeString: String {
        let s = Int(Date().timeIntervalSince(startedAt))
        return String(format: "%dh %02dm %02ds", s / 3600, (s % 3600) / 60, s % 60)
    }

    // MARK: Sensors

    private func startSensors() {
        appFocus.start { [weak self] patch in
            self?.ingest(patch)
        }
    }

    private func ingest(_ patch: ContextPatch) {
        patch.apply(&context)
        context.stamp = Date()
        eventCount += 1
        recentEvents.insert("\(timestamp()) \(patch.label)", at: 0)
        if recentEvents.count > 40 { recentEvents.removeLast() }
        scheduleEvaluate()
    }

    // MARK: Evaluation (debounced)

    private func scheduleEvaluate() {
        pendingEval?.cancel()
        let ms = configStore.config.settings.evaluationDebounceMs
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        pendingEval = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms), execute: work)
    }

    private func evaluate() {
        guard !automationPaused else { return }
        context.localTime = Date()
        let d = resolver.resolve(context: context, config: configStore.config, state: resolverState)
        decision = d
        // Advance state: an explicit active workspace becomes current; a keep/doNothing
        // decision leaves the current workspace untouched.
        if let ws = d.activeWorkspace {
            resolverState.activeWorkspace = ws
            resolverState.lastActive[ws] = Date()
        } else if d.target.action == .stop || d.target.action == .resumePrevious {
            resolverState.activeWorkspace = nil
        }
        applyAudio(d)
    }

    // MARK: Audio

    private func applyAudio(_ d: Decision) {
        var target = d.target
        // M1: external players aren't wired yet (that's M2). Rather than pretend, silence
        // the internal engine when a rule asks for an external source.
        if target.action == .play, let s = target.source, s.hasPrefix("external:") {
            target = AudioTarget(source: nil, action: .stop, volume: 0)
        }

        let command = reconciler.reconcile(current: audioState, target: target, transition: d.transition)
        engine.execute(command)

        // Optimistically mirror the command into our tracked state (matches the reconciler's
        // model, so we don't re-issue the same fade every context tick).
        switch command {
        case .start(let s, let v, _), .crossfade(let s, let v, _):
            audioState = AudioState(source: s, volume: v, playing: true)
        case .setVolume(let v, _):
            audioState.volume = v
        case .stop:
            audioState = .silent
        case .none:
            break
        }
        updateAudioStatus()
    }

    private func updateAudioStatus() {
        if audioState.playing, let s = audioState.source {
            let name = s.split(separator: ":").last.map(String.init) ?? s
            audioStatus = "playing \(name) · \(Int(audioState.volume * 100))%"
        } else if let d = decision, d.target.action == .play,
                  let s = d.target.source, s.hasPrefix("external:") {
            audioStatus = "→ external player (M2)"
        } else {
            audioStatus = "silent"
        }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
