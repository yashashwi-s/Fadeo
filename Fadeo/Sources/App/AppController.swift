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
                let stop = AudioCommand.stop(fadeMs: configStore.config.settings.defaults.fadeOutMs)
                switch activeActuator {
                case .internalEngine: engine.execute(stop)
                case .external: external.execute(stop)
                case .none: break
                }
                activeActuator = .none
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
    private let external = ExternalConductor()
    private let reconciler = Reconciler()
    private var audioState: AudioState = .silent
    /// Which actuator currently owns playback — needed because `.stop`/`.setVolume`
    /// commands don't carry a source string, so we route by "whoever's playing".
    private enum Actuator: Equatable { case none, internalEngine, external }
    private var activeActuator: Actuator = .none

    // Master level == the macOS system volume (single source of truth; see PLAN.md 6a).
    let systemVolume = SystemVolume()
    @Published var masterVolume: Float = 0.5

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

        // Master volume mirrors the system volume, live.
        systemVolume.onChange = { [weak self] v in self?.masterVolume = v }
        systemVolume.start()
        masterVolume = systemVolume.current() ?? 0.5

        startSensors()
        evaluate()
    }

    /// Setting Fadeo's master level sets the actual system volume (not a separate gain).
    func setMasterVolume(_ v: Float) {
        masterVolume = v
        systemVolume.set(v)
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
        let target = d.target
        let command = reconciler.reconcile(current: audioState, target: target, transition: d.transition)

        // Decide which actuator this command belongs to. A start/crossfade names its
        // source explicitly; a bare stop/setVolume applies to whichever actuator is
        // already playing (a rule never targets both at once).
        let destination: Actuator
        switch command {
        case .start(let s, _, _), .crossfade(let s, _, _):
            destination = s.hasPrefix("external:") ? .external : .internalEngine
        case .setVolume, .stop:
            destination = activeActuator
        case .none:
            destination = activeActuator
        }

        switch destination {
        case .internalEngine: engine.execute(command)
        case .external: external.execute(command)
        case .none: break
        }
        if case .start = command { activeActuator = destination }
        if case .crossfade = command { activeActuator = destination }
        if case .stop = command { activeActuator = .none }

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
        guard audioState.playing, let s = audioState.source else {
            audioStatus = "silent"
            return
        }
        let name = s.split(separator: ":").last.map(String.init) ?? s
        let via = activeActuator == .external ? "external · " : ""
        audioStatus = "playing \(via)\(name) · \(Int(audioState.volume * 100))%"
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
