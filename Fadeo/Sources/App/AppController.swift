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
    @Published var automationPaused = false { didSet { evaluate() } }

    let configStore: ConfigStore
    private let resolver = Resolver()
    private var resolverState = ResolverState()

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
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
