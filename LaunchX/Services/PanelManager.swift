import Cocoa
import Combine
import SwiftUI

class PanelManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = PanelManager()

    // Add @Published to satisfy ObservableObject protocol and allow UI observation
    @Published var isPanelVisible: Bool = false

    let openSettingsPublisher = PassthroughSubject<Void, Never>()

    private var panel: FloatingPanel!
    private var lastShowTime: Date = .distantPast

    private override init() {
        super.init()

        // Define standard size for the search window
        let panelSize = NSSize(width: 650, height: 500)
        let screenRect = NSScreen.main?.frame ?? .zero
        let centerOrigin = NSPoint(
            x: screenRect.midX - panelSize.width / 2,
            y: screenRect.midY - panelSize.height / 2)

        let rect = NSRect(origin: centerOrigin, size: panelSize)

        self.panel = FloatingPanel(contentRect: rect)

        // Set delegate to handle focus/key changes
        self.panel.delegate = self
    }

    /// Embeds the SwiftUI view into the panel
    func setup<Content: View>(rootView: Content) {
        // Use NSHostingView to render SwiftUI content in NSPanel
        let hostingView = NSHostingView(rootView: rootView)

        // Auto-layout constraints could be applied here if needed,
        // but typically the window frame dictates size or SwiftUI content dictates size.
        // For a spotlight-like app, usually fixed width, dynamic height.
        hostingView.autoresizingMask = [.width, .height]

        self.panel.contentView = hostingView
    }

    func togglePanel() {
        // Check actual window state as source of truth
        if panel.isVisible && NSApp.isActive {
            hidePanel(deactivateApp: true)
        } else {
            showPanel()
        }
    }

    func showPanel() {
        lastShowTime = Date()

        // Center on the main screen
        panel.center()

        // Ensure the app is active so it receives keyboard events immediately
        NSApp.activate(ignoringOtherApps: true)

        // Show the window
        panel.makeKeyAndOrderFront(nil)

        // Update state
        isPanelVisible = true
    }

    func hidePanel(deactivateApp: Bool = false) {
        panel.orderOut(nil)

        if deactivateApp {
            // Hide the application process so focus returns to the previous app
            NSApp.hide(nil)
        }

        // Update state
        isPanelVisible = false
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Check if it's our panel
        if let window = notification.object as? NSWindow, window == self.panel {
            // Ignore resign events that happen immediately after showing (grace period of 0.3s)
            if Date().timeIntervalSince(lastShowTime) < 0.3 {
                return
            }

            // Close the panel immediately when it loses focus (e.g. user clicks Settings or Desktop).
            // We do NOT deactivate the app here, because the user might have clicked
            // the Settings window (we want to stay active) or another app (already inactive).
            hidePanel(deactivateApp: false)
        }
    }
}
