import SwiftUI

@main
struct FadeoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var configStore: ConfigStore
    @StateObject private var controller: AppController
    @StateObject private var licenseManager = LicenseManager()

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
        }
        // .contentSize now that the shell is a deterministic HStack (not the old
        // NavigationSplitView whose buggy intrinsic sizing this used to fight): it makes
        // the window's minimum equal RootView's content minimum (~900pt), so the window
        // can never be dragged narrower than the content and clip it. The detail's
        // maxWidth .infinity leaves the maximum unbounded, so it still grows freely.
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }  // no File ▸ New

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
