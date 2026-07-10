import SwiftUI

/// The full-app sidebar shell. M0 ships the navigation, the live **Now** dashboard, and
/// a real **Preferences** pane; the remaining panes are placeholders that fill in across
/// M1–M4 behind this same structure.
enum Pane: String, CaseIterable, Identifiable {
    case now = "Now"
    case workspaces = "Workspaces"
    case soundLibrary = "Sound Library"
    case precedence = "Precedence"
    case triggers = "Triggers"
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
        case .preferences: return "gearshape"
        case .advanced: return "curlybraces"
        case .about: return "info.circle"
        }
    }

    var milestone: String? {
        switch self {
        case .now, .preferences, .about: return nil
        case .workspaces: return "M1 · M4"
        case .soundLibrary: return "M2 · M4"
        case .precedence: return "M2"
        case .triggers: return "M3"
        case .advanced: return "M4"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var controller: AppController
    // Dev/screenshot-verification hook: FADEO_INITIAL_PANE=<rawValue> jumps straight to a
    // pane at launch without needing UI-click automation. Never set in the shipped app.
    @State private var selection: Pane = Pane(rawValue: ProcessInfo.processInfo.environment["FADEO_INITIAL_PANE"] ?? "") ?? .now
    @State private var showOnboarding = !OnboardingSheet.hasCompleted

    var body: some View {
        content
            .sheet(isPresented: $showOnboarding) { OnboardingSheet(isPresented: $showOnboarding) }
    }

    private var content: some View {
        // Pin the sidebar open (constant visibility) and strip the collapse button below.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(Pane.allCases, selection: $selection) { pane in
                NavigationLink(value: pane) {
                    Label(pane.rawValue, systemImage: pane.systemImage)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
            .toolbar(removing: .sidebarToggle)     // remove the collapse button itself
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            Group {
                switch selection {
                case .now: NowPane()
                case .workspaces: WorkspacesPane()
                case .soundLibrary: SoundLibraryPane()
                case .precedence: PrecedencePane()
                case .triggers: TriggersPane()
                case .advanced: AdvancedPane()
                case .preferences: PreferencesPane()
                case .about: AboutPane()
                default: PlaceholderPane(pane: selection)
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
