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
    // Owned by FadeoApp (not local @State) so the Window menu's "Show Sidebar" command --
    // a hard reset to .all, not dependent on the toolbar toggle -- can reach the same
    // value. See SidebarState.swift for why that second path exists.
    @EnvironmentObject var sidebarState: SidebarState
    // Dev/screenshot-verification hook: FADEO_INITIAL_PANE=<rawValue> jumps straight to a
    // pane at launch without needing UI-click automation. Never set in the shipped app.
    @State private var selection: Pane = Pane(rawValue: ProcessInfo.processInfo.environment["FADEO_INITIAL_PANE"] ?? "") ?? .now
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

    private var content: some View {
        NavigationSplitView(columnVisibility: $sidebarState.visibility) {
            List(Pane.allCases, selection: $selection) { pane in
                NavigationLink(value: pane) {
                    Label(pane.rawValue, systemImage: pane.systemImage)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            Group {
                switch selection {
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
            .frame(minWidth: 560, minHeight: 520)
        }
        .frame(minWidth: 820, minHeight: 560)
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
