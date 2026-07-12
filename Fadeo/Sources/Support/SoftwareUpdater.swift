import Combine
import Sparkle

/// Thin ObservableObject wrapper around Sparkle's SPUStandardUpdaterController, so the
/// About/Preferences panes can bind to it without importing Sparkle themselves. Sparkle
/// owns its own update-prompt UI (with Install/Remind Me Later/Skip This Version built
/// in) -- this class only exposes the two knobs a user actually needs: a manual "Check
/// Now" trigger and the automatic-check toggle. Checked at most once/day
/// (SUScheduledCheckInterval in project.yml), never on every launch.
@MainActor
final class SoftwareUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = true
    @Published var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
        // Sparkle's own first-run consent alert ("Check for updates automatically?")
        // decides this asynchronously, after this object already read it once at init --
        // without this, the Preferences/About toggle would show a stale "off" even after
        // the user answered "Check Automatically" in that dialog.
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
