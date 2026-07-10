import SwiftUI

@main
struct FadeoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var configStore: ConfigStore
    @StateObject private var controller: AppController

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
        }
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }  // no File ▸ New

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(controller)
                .environmentObject(configStore)
        } label: {
            Image(systemName: "waveform")
        }
        .menuBarExtraStyle(.window)
    }
}
