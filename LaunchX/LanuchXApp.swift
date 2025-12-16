import SwiftUI

@main
struct LaunchXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use Settings to avoid creating a default WindowGroup window.
        // The actual main interface is managed by PanelManager.
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable automatic window tabbing (Sierra+)
        NSWindow.allowsAutomaticWindowTabbing = false

        // 1. Initialize the Search Panel
        PanelManager.shared.setup(rootView: ContentView())

        // 2. Setup Global HotKey (Option + Space)
        HotKeyService.shared.setupGlobalHotKey()

        // 3. Bind HotKey Action
        HotKeyService.shared.onHotKeyPressed = {
            PanelManager.shared.togglePanel()
        }
    }
}
