import SwiftUI

/// Lives above RootView (owned by FadeoApp) so both the window's own toggle button AND a
/// menu-bar command can control the same value. The toolbar's automatic sidebar toggle
/// has been unreliable in practice (confirmed live: it can get the sidebar stuck hidden
/// with no way back via the button itself) -- `forceShow()` is a second, independent path
/// that doesn't depend on that toggle working, bound to a real menu command with a
/// keyboard shortcut so it's reachable even if every on-screen control is misbehaving.
@MainActor
final class SidebarState: ObservableObject {
    @Published var visibility: NavigationSplitViewVisibility = .all

    func forceShow() {
        visibility = .all
    }
}
