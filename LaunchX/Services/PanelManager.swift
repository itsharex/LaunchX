import Cocoa

class PanelManager: NSObject, NSWindowDelegate {
    static let shared = PanelManager()

    private(set) var isPanelVisible: Bool = false

    // Callback to reset view state before hiding
    var onWillHide: (() -> Void)?
    // Callback when panel is about to show
    var onWillShow: (() -> Void)?

    private var panel: FloatingPanel!
    private var viewController: SearchPanelViewController?
    private var lastShowTime: Date = .distantPast
    private var isSetup = false

    // 用于快捷键触发 IDE 模式
    private var pendingIDEMode: (path: String, ideType: IDEType)?

    private override init() {
        super.init()
    }

    // 窗口尺寸常量
    private let panelWidth: CGFloat = 650
    private let panelExpandedHeight: CGFloat = 500

    // 计算窗口顶部应该在的Y坐标（基于展开后高度的中心位置）
    private func calculatePanelTopY() -> CGFloat {
        let screenRect = NSScreen.main?.frame ?? .zero
        // 以展开后的高度计算中心，返回窗口顶部的Y坐标
        return screenRect.midY + panelExpandedHeight / 2 + 100
    }

    /// Must be called once after app launches
    func setup() {
        guard !isSetup else { return }
        isSetup = true

        let initialHeight: CGFloat = 80
        let topY = calculatePanelTopY()
        // origin.y = 顶部Y - 窗口高度（macOS坐标系从左下角开始）
        let originY = topY - initialHeight
        let originX = (NSScreen.main?.frame.midX ?? 0) - panelWidth / 2

        let rect = NSRect(
            origin: NSPoint(x: originX, y: originY),
            size: NSSize(width: panelWidth, height: initialHeight))

        self.panel = FloatingPanel(contentRect: rect)
        self.panel.delegate = self

        // Setup AppKit view controller
        viewController = SearchPanelViewController()
        panel.contentView = viewController?.view
    }

    func togglePanel() {
        guard isSetup else { return }

        if panel.isVisible && NSApp.isActive {
            // 检查是否有其他窗口（如设置窗口）打开
            let hasOtherVisibleWindows = NSApp.windows.contains { window in
                window != panel && window.isVisible && !window.isKind(of: NSPanel.self)
            }
            hidePanel(deactivateApp: !hasOtherVisibleWindows)
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard isSetup else { return }

        lastShowTime = Date()

        // Notify before showing
        onWillShow?()

        // 保持窗口顶部位置一致（基于展开后高度计算）
        let topY = calculatePanelTopY()
        let currentHeight = panel.frame.height
        let originY = topY - currentHeight
        let originX = (NSScreen.main?.frame.midX ?? 0) - panelWidth / 2
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Focus the search field
        viewController?.focus()

        isPanelVisible = true
    }

    func hidePanel(deactivateApp: Bool = false) {
        guard isSetup else { return }

        // Reset state BEFORE hiding
        onWillHide?()
        viewController?.resetState()

        panel.orderOut(nil)

        if deactivateApp {
            NSApp.hide(nil)
        }

        isPanelVisible = false
    }

    // MARK: - IDE 模式入口

    /// 以 IDE 模式显示面板（用于快捷键触发）
    /// - Parameters:
    ///   - idePath: IDE 应用路径
    ///   - ideType: IDE 类型
    func showPanelInIDEMode(idePath: String, ideType: IDEType) {
        guard isSetup else { return }

        // 发送通知让 SearchPanelViewController 进入 IDE 模式
        NotificationCenter.default.post(
            name: .enterIDEModeDirectly,
            object: nil,
            userInfo: ["path": idePath, "ideType": ideType]
        )

        // 显示面板
        showPanel()
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard isSetup else { return }

        if let window = notification.object as? NSWindow, window == self.panel {
            if Date().timeIntervalSince(lastShowTime) < 0.3 {
                return
            }
            hidePanel(deactivateApp: false)
        }
    }
}
