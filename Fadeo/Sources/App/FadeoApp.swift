import SwiftUI

@main
struct FadeoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var configStore: ConfigStore
    @StateObject private var controller: AppController
    @StateObject private var licenseManager = LicenseManager()
    @StateObject private var softwareUpdater = SoftwareUpdater()
    @StateObject private var sidebarState = SidebarState()

    init() {
        // One ConfigStore, shared by the controller and the UI.
        let store = ConfigStore()
        _configStore = StateObject(wrappedValue: store)
        _controller = StateObject(wrappedValue: AppController(configStore: store))
    }

    var body: some Scene {
        Window("Fadeo", id: "main") {
            RootView()
                .environmentObject(controller)
                .environmentObject(configStore)
                .environmentObject(licenseManager)
                .environmentObject(softwareUpdater)
                .environmentObject(sidebarState)
        }
        // .contentSize (the previous setting) ties window resizing tightly to the
        // content's intrinsic size, which doesn't mix well with a NavigationSplitView
        // whose columns are themselves user-resizable -- a likely contributor to a
        // resize-triggered layout corruption reported live (scrolling breaking, stray
        // content bleeding through at the window edge). .automatic is the standard,
        // well-tested choice for a freely resizable sidebar-based window.
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}  // no File ▸ New
            // A hard reset to .all, independent of the toolbar's own sidebar toggle --
            // that button has been unreliable in practice (confirmed live: the sidebar
            // could get stuck hidden with no on-screen way back). Always reachable via
            // the View menu and its shortcut even if every other control misbehaves.
            CommandGroup(after: .sidebar) {
                Button("Show Sidebar") { sidebarState.forceShow() }
                    .keyboardShortcut("0", modifiers: [.command, .option])
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(controller)
                .environmentObject(configStore)
        } label: {
            // A small colored dot next to the icon names which workspace is live, without
            // requiring a click — the same "colored dot = workspace" language used
            // everywhere else in the app (sidebar, this menu's own dropdown header).
            HStack(spacing: 3) {
                Image(systemName: "waveform")
                if let ws = controller.activeWorkspaceForDisplay {
                    Circle().fill(Brand.swatch(ws.color)).frame(width: 6, height: 6)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
