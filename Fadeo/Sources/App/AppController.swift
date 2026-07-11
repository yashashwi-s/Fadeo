import Foundation
import AppKit
import Combine
import FadeoCore

/// The app's brain: sensors feed Context, which resolves to a Decision, which drives the
/// InternalEngine/ExternalConductor actuators. Exposes live state for the dashboard and
/// menu bar. No polling anywhere: every update is driven by an OS push through a sensor.
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
    let usageStore = UsageStore()
    private let resolver = Resolver()
    private var resolverState = ResolverState()
    private var usageTrackedWorkspaceID: String?
    private var usageTrackedSince = Date()

    // Audio actuation
    private let engine = InternalEngine()
    private let external = ExternalConductor()
    private let reconciler = Reconciler()
    private var audioState: AudioState = .silent
    /// Which actuator currently owns playback, needed because `.stop`/`.setVolume`
    /// commands don't carry a source string, so we route by "whoever's playing".
    private enum Actuator: Equatable { case none, internalEngine, external }
    private var activeActuator: Actuator = .none

    // Preview: a dedicated engine so auditioning a sound in the editor never touches the
    // live pipeline's tracked state. While previewing, evaluate() is suppressed and the
    // live output is silenced; stopping preview re-applies the active workspace's audio.
    private let previewEngine = InternalEngine()
    @Published private(set) var previewingSource: String?
    private var isPreviewing: Bool { previewingSource != nil }

    // Sensors, lazily activated: a sensor whose fields no enabled workspace references
    // is never started (zero observers, zero cost). See requiredFields()/reconcileSensors().
    private let appFocus = AppFocusSensor()
    private let spaceSensor = SpaceSensor()
    private let meetingSensor = MeetingSensor()
    private let focusSensor = FocusSensor()
    private let scheduleSensor = ScheduleSensor()
    private lazy var allSensors: [any Sensor] = [appFocus, spaceSensor, meetingSensor, focusSensor, scheduleSensor]
    private var runningSensors: Set<ObjectIdentifier> = []

    // Debounce
    private var pendingEval: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    // Switch gating (enter delay / exit delay / minimum dwell). One armed timer at most;
    // any evaluation that re-affirms the current workspace cancels it, so a switch only
    // commits if the new target held continuously for its grace period.
    private var pendingSwitch: (target: String?, work: DispatchWorkItem)?
    private var lastSwitchAt: Date = .distantPast

    let startedAt = Date()

    init(configStore: ConfigStore) {
        self.configStore = configStore

        engine.updateLocalPlaylists(configStore.config.localPlaylists)
        scheduleSensor.reschedule(workspaces: configStore.config.workspaces)

        // Re-evaluate whenever the config hot-reloads.
        // @Published fires its publisher from willSet, before the backing storage is
        // actually updated. Reading `configStore.config` synchronously inside this sink
        // would still see the OLD value (a well-known Combine footgun). Dispatching to the
        // next run loop turn (still same-frame, imperceptible) ensures reconcileSensors()/
        // evaluate() (which both read configStore.config directly rather than a passed
        // parameter, for API simplicity) see the config that's actually now in effect.
        configStore.$config
            .dropFirst()
            .sink { [weak self] cfg in
                guard let self else { return }
                self.engine.updateLocalPlaylists(cfg.localPlaylists)
                self.scheduleSensor.reschedule(workspaces: cfg.workspaces)
                DispatchQueue.main.async {
                    self.reconcileSensors()
                    self.evaluate()
                }
            }
            .store(in: &cancellables)

        reconcileSensors()
        evaluate()

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.recordUsageIfWorkspaceChanged(newWorkspaceID: nil)
                self.usageStore.flush()
            }
        }
    }

    var activeWorkspaceName: String? {
        guard let id = resolverState.activeWorkspace else { return nil }
        return configStore.config.workspaces.first { $0.id == id }?.name
    }

    // MARK: Sensor status (for the Triggers pane)

    struct SensorStatus: Identifiable {
        let id: String
        let name: String
        let running: Bool
        let fields: [String]
    }

    /// Which context sensors are currently active (for honest Now-pane labels — an
    /// unreferenced sensor is off by lazy activation, not unimplemented).
    var spaceTracked: Bool { runningSensors.contains(ObjectIdentifier(spaceSensor)) }
    var meetingTracked: Bool { runningSensors.contains(ObjectIdentifier(meetingSensor)) }
    var focusTracked: Bool { runningSensors.contains(ObjectIdentifier(focusSensor)) }

    var sensorStatuses: [SensorStatus] {
        let names: [(String, String)] = [
            ("AppFocusSensor", "App Focus"), ("SpaceSensor", "Desktop / Space"),
            ("MeetingSensor", "Meeting"), ("FocusSensor", "Focus Mode"), ("ScheduleSensor", "Time / Schedule"),
        ]
        return allSensors.enumerated().map { i, sensor in
            let (_, label) = names[i]
            return SensorStatus(
                id: String(describing: type(of: sensor)),
                name: label,
                running: runningSensors.contains(ObjectIdentifier(sensor)),
                fields: type(of: sensor).providedFields.map(\.rawValue).sorted()
            )
        }
    }

    var uptimeString: String {
        let s = Int(Date().timeIntervalSince(startedAt))
        return String(format: "%dh %02dm %02ds", s / 3600, (s % 3600) / 60, s % 60)
    }

    // MARK: Sensors (lazy activation)

    /// The union of Context fields any enabled workspace's `match` actually references,
    /// plus `.app` unconditionally (the core trigger, and what fallback/stickiness reason
    /// about). Only sensors providing one of these fields are started.
    private func requiredFields(_ workspaces: [Workspace]) -> Set<ContextField> {
        var fields: Set<ContextField> = [.app]
        for ws in workspaces where ws.enabled {
            let m = ws.match
            if !m.apps.isEmpty { fields.insert(.app) }
            if !m.spaces.isEmpty { fields.insert(.space) }
            if !m.focus.isEmpty { fields.insert(.focus) }
            if m.meeting != nil { fields.formUnion([.meeting, .camera, .mic]) }
            if m.timeBetween != nil { fields.insert(.time) }
            if !m.weekdays.isEmpty { fields.insert(.weekday) }
        }
        return fields
    }

    private func reconcileSensors() {
        let required = requiredFields(configStore.config.workspaces)
        for sensor in allSensors {
            let id = ObjectIdentifier(sensor)
            let needed = !type(of: sensor).providedFields.isDisjoint(with: required)
            if needed && !runningSensors.contains(id) {
                sensor.start { [weak self] patch in self?.ingest(patch) }
                runningSensors.insert(id)
            } else if !needed && runningSensors.contains(id) {
                sensor.stop()
                runningSensors.remove(id)
            }
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

    // MARK: Preview (audition a sound in the editor)

    /// Play an internal source (preset/file/folder) on the dedicated preview engine.
    /// External sources aren't previewed here — auditioning them would mean driving the
    /// very same Music/Spotify session the workspace already uses, so the editor offers
    /// no preview for those. Toggling the same source off stops it.
    func togglePreview(_ sound: Sound) {
        guard let source = sound.source, source.hasPrefix("internal:") else { return }
        if previewingSource == source {
            stopPreview()
            return
        }
        // First time entering preview: silence the live output and reset tracked state
        // so it re-applies cleanly when preview ends. (audioState left stale would make
        // the reconciler think nothing changed and never restart the workspace's audio.)
        if !isPreviewing {
            engine.execute(.stop(fadeMs: 150))
            external.execute(.stop(fadeMs: 150))
            audioState = .silent
            activeActuator = .none
        }
        previewEngine.updateLocalPlaylists(configStore.config.localPlaylists)
        previewEngine.execute(.stop(fadeMs: 0))
        previewEngine.execute(
            .start(source: source, volume: sound.volume, fadeMs: 150),
            order: sound.order, repeatMode: sound.repeatMode
        )
        previewingSource = source
    }

    func stopPreview() {
        guard isPreviewing else { return }
        previewEngine.execute(.stop(fadeMs: 150))
        previewingSource = nil
        // Re-apply the live workspace audio once the preview has faded.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.evaluate() }
    }

    private func evaluate() {
        guard !automationPaused, !isPreviewing else { return }
        context.localTime = Date()
        let d = resolver.resolve(context: context, config: configStore.config, state: resolverState)
        decision = d   // the Now pane always shows the live resolution, gated or not

        let current = resolverState.activeWorkspace
        let isSwitch = switchesAway(d, from: current)

        guard isSwitch else {
            // Re-affirms the current state (same workspace, or a keep-current fallback).
            // Cancel any armed switch — the user came back within the grace window,
            // which is exactly what enter/exit delay exist for.
            cancelPendingSwitch()
            commit(d)
            return
        }

        // Overrides pre-empt everything, including their own grace: a "Meetings" pause
        // that waited out an enter delay would defeat its purpose.
        if d.reason.band == .override {
            cancelPendingSwitch()
            commit(d)
            return
        }

        let delayMs = switchGateMs(decision: d, current: current)
        if delayMs <= 0 {
            cancelPendingSwitch()
            commit(d)
            return
        }

        // A timer toward this same target is already running: let it ride (its deadline
        // marks when the target has held long enough). A different target re-arms.
        if pendingSwitch?.target == d.activeWorkspace { return }
        cancelPendingSwitch()
        let target = d.activeWorkspace
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSwitch = nil
            self.context.localTime = Date()
            let fresh = self.resolver.resolve(context: self.context, config: self.configStore.config, state: self.resolverState)
            self.decision = fresh
            if fresh.activeWorkspace == target {
                self.commit(fresh)       // target held for the whole grace period
            } else {
                self.evaluate()          // world moved on; gate whatever wins now
            }
        }
        pendingSwitch = (target, work)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: work)
    }

    /// Whether this decision moves away from the current workspace (to another one, or
    /// to a real stop) — as opposed to re-affirming it or a keep-current fallback.
    private func switchesAway(_ d: Decision, from current: String?) -> Bool {
        if let target = d.activeWorkspace { return target != current }
        // No winner: only an actual stop/resume leaves the current workspace.
        return current != nil && (d.target.action == .stop || d.target.action == .resumePrevious)
    }

    /// The gate for a switch: the larger of (remaining minimum dwell of the current
    /// workspace) and (the incoming workspace's enter delay, or the outgoing one's exit
    /// delay when falling to silence). No gate at all when nothing is active — there is
    /// nothing to protect, and first playback should be instant.
    private func switchGateMs(decision d: Decision, current: String?) -> Int {
        let defaults = configStore.config.settings.defaults
        guard let current, let currentWS = configStore.config.workspaces.first(where: { $0.id == current }) else {
            return 0
        }
        let currentTiming = currentWS.timing.resolved(over: defaults)
        let dwellRemaining = currentTiming.minDwellMs - Int(Date().timeIntervalSince(lastSwitchAt) * 1000)

        let grace: Int
        if let targetID = d.activeWorkspace,
           let targetWS = configStore.config.workspaces.first(where: { $0.id == targetID }) {
            grace = targetWS.timing.resolved(over: defaults).enterDelayMs
        } else {
            grace = currentTiming.exitDelayMs
        }
        return max(dwellRemaining, grace, 0)
    }

    private func cancelPendingSwitch() {
        pendingSwitch?.work.cancel()
        pendingSwitch = nil
    }

    /// Actually advance state and drive audio — the formerly-unconditional tail of
    /// `evaluate()`, now only reached once a switch has cleared its gate.
    private func commit(_ d: Decision) {
        let before = resolverState.activeWorkspace
        if let ws = d.activeWorkspace {
            resolverState.activeWorkspace = ws
            resolverState.lastActive[ws] = Date()
        } else if d.target.action == .stop || d.target.action == .resumePrevious {
            resolverState.activeWorkspace = nil
        }
        if resolverState.activeWorkspace != before { lastSwitchAt = Date() }
        recordUsageIfWorkspaceChanged(newWorkspaceID: d.activeWorkspace)
        applyAudio(d)
    }

    // MARK: Usage tracking (genuine switches only, no polling)

    private func recordUsageIfWorkspaceChanged(newWorkspaceID: String?) {
        guard newWorkspaceID != usageTrackedWorkspaceID else { return }
        let now = Date()
        usageStore.recordElapsed(
            workspaceID: usageTrackedWorkspaceID,
            seconds: now.timeIntervalSince(usageTrackedSince)
        )
        if let newWorkspaceID {
            usageStore.recordActivation(workspaceID: newWorkspaceID)
        }
        usageTrackedWorkspaceID = newWorkspaceID
        usageTrackedSince = now
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

        // If this command is about to hand playback to a DIFFERENT actuator than the one
        // currently playing, explicitly stop the one being left behind first. The
        // Reconciler only diffs source strings, it has no notion of actuator identity,
        // so without this, switching e.g. an internal preset to an external Spotify/Music
        // source would leave the internal engine running invisibly forever (confirmed as
        // a real bug: reported as "white noise still playing" after switching a
        // workspace's source to Apple Music).
        let isHandoff: Bool
        switch command {
        case .start, .crossfade: isHandoff = destination != activeActuator && activeActuator != .none
        case .none, .setVolume, .stop: isHandoff = false
        }
        if isHandoff {
            let fadeMs = { if case .crossfade = command { return d.transition.timing.crossfadeMs }
                           return d.transition.timing.fadeOutMs }()
            let vacate = AudioCommand.stop(fadeMs: fadeMs)
            switch activeActuator {
            case .internalEngine: engine.execute(vacate)
            case .external: external.execute(vacate)
            case .none: break
            }
        }

        switch destination {
        case .internalEngine: engine.execute(command, order: target.order, repeatMode: target.repeatMode)
        case .external: external.execute(command, order: target.order, repeatMode: target.repeatMode)
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
