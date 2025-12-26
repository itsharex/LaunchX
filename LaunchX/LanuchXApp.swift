import Combine
import SwiftUI

@main
struct LaunchXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use Settings to avoid creating a default WindowGroup window.
        // The actual main interface is managed by PanelManager.
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: NSStatusBar!
    var statusItem: NSStatusItem!
    var onboardingWindow: NSWindow?
    var isQuitting = false
    private var permissionObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // 先不设置 activation policy，等权限检查后决定
        // 如果需要显示引导页，保持 regular 模式
        // 如果权限已全部授予，再切换到 accessory 模式

        // Disable automatic window tabbing (Sierra+)
        NSWindow.allowsAutomaticWindowTabbing = false

        // 1. Initialize the Search Panel (pure AppKit, no SwiftUI)
        PanelManager.shared.setup()

        // 2. Check permissions first before setting up hotkey
        checkPermissionsAndSetup()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        print("LaunchX: applicationDidBecomeActive called")
        // 如果引导页窗口存在但不可见，强制显示
        if let window = onboardingWindow, !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func checkPermissionsAndSetup() {
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")

        // 同步检查辅助功能权限（这是最重要的权限）
        let hasAccessibility = AXIsProcessTrusted()

        print("LaunchX: isFirstLaunch=\(isFirstLaunch), hasAccessibility=\(hasAccessibility)")

        // 异步更新其他权限状态（用于 UI 显示）
        PermissionService.shared.checkAllPermissions()

        // 等待权限状态更新后检查是否所有权限都已授予
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            let allGranted = PermissionService.shared.allPermissionsGranted
            let accessibility = PermissionService.shared.isAccessibilityGranted
            let screenRecording = PermissionService.shared.isScreenRecordingGranted
            let fullDisk = PermissionService.shared.isFullDiskAccessGranted

            print(
                "LaunchX: allGranted=\(allGranted), accessibility=\(accessibility), screenRecording=\(screenRecording), fullDisk=\(fullDisk)"
            )

            if isFirstLaunch {
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                print("LaunchX: First launch, opening onboarding")
                self.openOnboarding()
            } else if !allGranted {
                print("LaunchX: Not all permissions granted, opening onboarding")
                // 非首次启动但权限未全部授予，显示引导页
                self.openOnboarding()
                // 如果辅助功能已授权，先设置热键
                if hasAccessibility {
                    self.setupHotKey()
                }
            } else {
                print("LaunchX: All permissions granted, showing panel")
                // 所有权限已授予，切换到 accessory 模式并显示面板
                NSApp.setActivationPolicy(.accessory)
                self.setupHotKeyAndShowPanel()
            }

            // 监听权限变化，当辅助功能权限授予后设置热键
            self.observePermissionChanges()
        }
    }

    private func observePermissionChanges() {
        permissionObserver = PermissionService.shared.$isAccessibilityGranted
            .removeDuplicates()
            .sink { [weak self] isGranted in
                if isGranted {
                    self?.setupHotKey()
                }
            }
    }

    private func setupHotKey() {
        // 只有辅助功能权限授予后才设置热键
        guard AXIsProcessTrusted() else { return }

        // Setup Global HotKey (Option + Space)
        HotKeyService.shared.setupGlobalHotKey()

        // Bind HotKey Action
        HotKeyService.shared.onHotKeyPressed = {
            PanelManager.shared.togglePanel()
        }

        // 设置自定义快捷键回调
        setupCustomHotKeys()

        print("LaunchX: HotKey setup complete")
    }

    /// 设置自定义快捷键
    private func setupCustomHotKeys() {
        // 设置自定义快捷键触发回调
        HotKeyService.shared.onCustomHotKeyPressed = { [weak self] itemId, isExtension in
            self?.handleCustomHotKey(itemId: itemId, isExtension: isExtension)
        }

        // 从配置加载已保存的自定义快捷键
        let config = CustomItemsConfig.load()
        HotKeyService.shared.reloadCustomHotKeys(from: config)

        print("LaunchX: Custom hotkeys loaded")
    }

    /// 处理自定义快捷键触发
    private func handleCustomHotKey(itemId: UUID, isExtension: Bool) {
        let config = CustomItemsConfig.load()
        guard let item = config.item(byId: itemId) else {
            print("LaunchX: Custom hotkey triggered but item not found: \(itemId)")
            return
        }

        if isExtension, let ideType = item.ideType {
            // 进入扩展模式：显示面板并进入 IDE 项目模式
            print("LaunchX: Opening IDE mode for \(item.name)")
            PanelManager.shared.showPanelInIDEMode(idePath: item.path, ideType: ideType)
        } else {
            // 直接打开应用或文件夹
            print("LaunchX: Opening \(item.path)")
            NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
        }
    }

    private func setupHotKeyAndShowPanel() {
        setupHotKey()
        // 显示搜索面板
        PanelManager.shared.togglePanel()
    }

    func openOnboarding() {
        print("LaunchX: Opening onboarding window")

        if onboardingWindow == nil {
            let rootView = OnboardingView { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                // 关闭引导页后切换为 accessory app
                NSApp.setActivationPolicy(.accessory)
                // 设置热键并显示面板
                self?.setupHotKeyAndShowPanel()
            }

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: rootView)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.title = "欢迎使用 LaunchX"

            // Hide zoom and minimize buttons for a cleaner look
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true

            onboardingWindow = window
        }

        // 启动时已经是 regular 模式，直接显示窗口
        onboardingWindow?.center()
        onboardingWindow?.makeKeyAndOrderFront(nil)
        onboardingWindow?.orderFrontRegardless()  // 强制到最前面
        NSApp.activate(ignoringOtherApps: true)

        print("LaunchX: Onboarding window frame: \(onboardingWindow?.frame ?? .zero)")
        print("LaunchX: Onboarding window isVisible: \(onboardingWindow?.isVisible ?? false)")
    }

    func setupStatusItem() {
        statusBar = NSStatusBar()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.Name("StatusBarIcon"))
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(title: "打开 LaunchX", action: #selector(togglePanel), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(explicitQuit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func togglePanel() {
        PanelManager.shared.togglePanel()
    }

    @objc func openSettings() {
        PanelManager.shared.hidePanel(deactivateApp: false)
        // Send action to open the Settings window defined in the App struct
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func explicitQuit() {
        isQuitting = true
        NSApp.terminate(nil)
    }

    // Intercept termination request (Cmd+Q) to keep the app running in the background
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isQuitting {
            return .terminateNow
        }

        // Close all windows (Settings, Onboarding, etc.) but keep the app running
        for window in NSApp.windows {
            window.close()
        }

        // Hide the application
        NSApp.hide(nil)

        return .terminateCancel
    }
}
