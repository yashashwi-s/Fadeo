import SwiftUI

/// The full-app sidebar shell. Every pane is implemented; RootView's switch below routes
/// each `Pane` case to its real view directly (no fallback path).
enum Pane: String, CaseIterable, Identifiable {
    case now = "Now"
    case workspaces = "Workspaces"
    case soundLibrary = "Sound Library"
    case precedence = "Precedence"
    case triggers = "Triggers"
    case usage = "Usage"
    case preferences = "Preferences"
    case advanced = "Advanced"
    case about = "About"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .now: return "waveform"
        case .workspaces: return "square.stack.3d.up"
        case .soundLibrary: return "music.note.list"
        case .precedence: return "arrow.triangle.branch"
        case .triggers: return "sensor.tag.radiowaves.forward"
        case .usage: return "chart.bar"
        case .preferences: return "gearshape"
        case .advanced: return "curlybraces"
        case .about: return "info.circle"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var licenseManager: LicenseManager
    // Dev/screenshot-verification hook: FADEO_INITIAL_PANE=<rawValue> jumps straight to a
    // pane at launch without needing UI-click automation. Never set in the shipped app.
    @State private var selection: Pane? = Pane(rawValue: ProcessInfo.processInfo.environment["FADEO_INITIAL_PANE"] ?? "") ?? .now
    @State private var showOnboarding = !OnboardingSheet.hasCompleted
    @State private var showNag = false

    var body: some View {
        content
            .sheet(isPresented: $showOnboarding) { OnboardingSheet(isPresented: $showOnboarding) }
            .sheet(isPresented: $showNag) { NagSheet(licenseManager: licenseManager, isPresented: $showNag) }
            .onChange(of: showOnboarding) { _, stillShowing in
                if !stillShowing { showNag = licenseManager.shouldShowNag }
            }
            .onAppear {
                if !showOnboarding { showNag = licenseManager.shouldShowNag }
            }
    }

    // A plain HStack shell, deliberately NOT a NavigationSplitView: the sidebar is a
    // fixed-width column that can never be collapsed (no toolbar toggle, no draggable
    // divider) and there is no autosaved split geometry to corrupt. The detail is wrapped
    // in a NavigationStack purely so each pane's `.navigationTitle(...)` still renders in
    // the titlebar (the app has no push navigation). This replaced a NavigationSplitView
    // whose inherent collapse behavior and beta-buggy height computation caused the
    // sidebar to vanish and the panes' ScrollViews to break on window resize.
    private var content: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 216)
            Divider()
            NavigationStack {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // minWidth must clear the widest pane's own minimum so nothing clips at the right
        // edge: sidebar 216 + Workspaces' list (min 220) + its editor (min 460) + dividers
        // ~= 900. Paired with .windowResizability(.contentSize) in FadeoApp, this becomes a
        // hard window floor; the detail's maxWidth .infinity keeps it freely growable above.
        .frame(minWidth: 900, idealWidth: 1120, minHeight: 600, idealHeight: 760)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(Pane.allCases) { pane in
                    Label(pane.rawValue, systemImage: pane.systemImage).tag(pane)
                }
            }
            .listStyle(.sidebar)
            sidebarFooter
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .now {
        case .now: NowPane()
        case .workspaces: WorkspacesPane()
        case .soundLibrary: SoundLibraryPane()
        case .precedence: PrecedencePane()
        case .triggers: TriggersPane()
        case .usage: UsagePane(usageStore: controller.usageStore)
        case .advanced: AdvancedPane()
        case .preferences: PreferencesPane()
        case .about: AboutPane()
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.secondary.opacity(controller.automationPaused ? 0.4 : 0.8))
                .frame(width: 7, height: 7)
            Text(controller.automationPaused ? "Paused" : "Active")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}
