import Cocoa

/// Pure AppKit implementation of the search panel - no SwiftUI overhead
class SearchPanelViewController: NSViewController {

    // MARK: - UI Components
    private let searchField = NSTextField()
    private let searchIcon = NSImageView()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let divider = NSBox()
    private let noResultsLabel = NSTextField(labelWithString: "No results found.")

    // MARK: - State
    private var results: [SearchResult] = []
    private var recentApps: [SearchResult] = []  // 最近使用的应用
    private var selectedIndex: Int = 0
    private let searchEngine = SearchEngine.shared
    private var isShowingRecents: Bool = false  // 是否正在显示最近使用

    // MARK: - Constants
    private let rowHeight: CGFloat = 44
    private let headerHeight: CGFloat = 80

    // MARK: - Lifecycle

    override func loadView() {
        // Create visual effect view with rounded corners
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true

        self.view = visualEffectView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupKeyboardMonitor()

        // SearchEngine handles indexing automatically on init
        // Just trigger a reference to ensure it starts
        _ = searchEngine.isReady

        // 加载最近使用的应用
        loadRecentApps()

        // Register for panel hide callback
        PanelManager.shared.onWillHide = { [weak self] in
            self?.resetState()
        }
    }

    // MARK: - Setup

    private func setupUI() {
        // Search icon
        searchIcon.image = NSImage(
            systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchIcon)

        // Search field
        searchField.placeholderString = "LaunchX Search..."
        searchField.isBordered = false
        searchField.backgroundColor = .clear
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 26, weight: .light)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchField)

        // Divider
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.isHidden = true
        view.addSubview(divider)

        // Table view setup
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ResultColumn"))
        column.width = 610
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = rowHeight
        tableView.delegate = self
        tableView.dataSource = self
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = NSSize(width: 0, height: 0)

        // Scroll view
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isHidden = true
        view.addSubview(scrollView)

        // No results label
        noResultsLabel.textColor = .secondaryLabelColor
        noResultsLabel.alignment = .center
        noResultsLabel.translatesAutoresizingMaskIntoConstraints = false
        noResultsLabel.isHidden = true
        view.addSubview(noResultsLabel)

        // Constraints
        NSLayoutConstraint.activate([
            // Search icon
            searchIcon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            searchIcon.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 40),
            searchIcon.widthAnchor.constraint(equalToConstant: 22),
            searchIcon.heightAnchor.constraint(equalToConstant: 22),

            // Search field
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -20),
            searchField.centerYAnchor.constraint(equalTo: searchIcon.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 32),

            // Divider
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.topAnchor.constraint(equalTo: view.topAnchor, constant: headerHeight),

            // Scroll view
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // No results label
            noResultsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            noResultsLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 20),
        ])
    }

    private var keyboardMonitor: Any?

    private func setupKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self = self,
                let window = self.view.window,
                window.isVisible,
                window.isKeyWindow
            else {
                return event
            }
            return self.handleKeyEvent(event)
        }
    }

    deinit {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Public Methods

    func focus() {
        view.window?.makeFirstResponder(searchField)

        // 每次显示面板时刷新状态，确保设置更改立即生效
        refreshDisplayMode()
    }

    /// 刷新显示模式（Simple/Full）
    private func refreshDisplayMode() {
        let defaultWindowMode =
            UserDefaults.standard.string(forKey: "defaultWindowMode") ?? "simple"

        if searchField.stringValue.isEmpty {
            if defaultWindowMode == "full" && !recentApps.isEmpty {
                results = recentApps
                isShowingRecents = true
            } else {
                results = []
                isShowingRecents = false
            }
            selectedIndex = 0
            tableView.reloadData()
        }

        updateVisibility()
    }

    func resetState() {
        searchField.stringValue = ""
        selectedIndex = 0

        // Full 模式下显示最近使用的应用
        let defaultWindowMode =
            UserDefaults.standard.string(forKey: "defaultWindowMode") ?? "simple"
        if defaultWindowMode == "full" && !recentApps.isEmpty {
            results = recentApps
            isShowingRecents = true
        } else {
            results = []
            isShowingRecents = false
        }

        tableView.reloadData()
        updateVisibility()
    }

    // MARK: - Search

    private func performSearch(_ query: String) {
        guard !query.isEmpty else {
            selectedIndex = 0

            // Full 模式下显示最近使用的应用
            let defaultWindowMode =
                UserDefaults.standard.string(forKey: "defaultWindowMode") ?? "simple"
            if defaultWindowMode == "full" && !recentApps.isEmpty {
                results = recentApps
                isShowingRecents = true
            } else {
                results = []
                isShowingRecents = false
            }

            tableView.reloadData()
            updateVisibility()
            return
        }

        isShowingRecents = false
        let searchResults = searchEngine.searchSync(text: query)
        results = searchResults
        selectedIndex = results.isEmpty ? 0 : 0
        tableView.reloadData()
        updateVisibility()

        if !results.isEmpty {
            tableView.selectRowIndexes(
                IndexSet(integer: selectedIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(selectedIndex)
        }
    }

    private func updateVisibility() {
        let hasQuery = !searchField.stringValue.isEmpty
        let hasResults = !results.isEmpty
        let defaultWindowMode =
            UserDefaults.standard.string(forKey: "defaultWindowMode") ?? "simple"

        divider.isHidden = !hasQuery && !isShowingRecents
        scrollView.isHidden = !hasResults
        noResultsLabel.isHidden = !hasQuery || hasResults

        // Update window height
        if defaultWindowMode == "full" {
            // Full 模式：始终展开
            updateWindowHeight(expanded: true)
        } else {
            // Simple 模式：有搜索内容且有结果时展开
            updateWindowHeight(expanded: hasQuery && hasResults)
        }
    }

    private func updateWindowHeight(expanded: Bool) {
        guard let window = view.window else { return }

        // Read user's default window mode preference
        let defaultWindowMode =
            UserDefaults.standard.string(forKey: "defaultWindowMode") ?? "simple"

        // If user prefers "full" mode, always show expanded view when there's a query
        // If "simple" mode, only expand when there are results
        let shouldExpand: Bool
        if defaultWindowMode == "full" {
            shouldExpand = expanded  // Expand whenever there's a query
        } else {
            shouldExpand = expanded && !results.isEmpty  // Simple mode: only expand with results
        }

        let targetHeight: CGFloat = shouldExpand ? 500 : 80
        let currentFrame = window.frame

        guard abs(currentFrame.height - targetHeight) > 1 else { return }

        let newOriginY = currentFrame.origin.y - (targetHeight - currentFrame.height)
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: newOriginY,
            width: currentFrame.width,
            height: targetHeight
        )

        // No animation for speed
        window.setFrame(newFrame, display: true, animate: false)
    }

    // MARK: - Keyboard Handling

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // 检查输入法是否正在组合输入（如中文输入法）
        var isComposing = false
        if let fieldEditor = searchField.currentEditor() as? NSTextView {
            isComposing = fieldEditor.markedRange().length > 0
        }

        switch Int(event.keyCode) {
        case 125:  // Down arrow
            if isComposing { return event }  // 让输入法处理
            moveSelectionDown()
            return nil
        case 126:  // Up arrow
            if isComposing { return event }  // 让输入法处理
            moveSelectionUp()
            return nil
        case 53:  // Escape
            if isComposing { return event }  // 让输入法取消
            PanelManager.shared.hidePanel()
            return nil
        case 36:  // Return
            if isComposing { return event }  // 让输入法确认输入
            openSelected()
            return nil
        default:
            // Ctrl+N / Ctrl+P
            if event.modifierFlags.contains(.control) {
                if event.keyCode == 45 {  // N
                    moveSelectionDown()
                    return nil
                } else if event.keyCode == 35 {  // P
                    moveSelectionUp()
                    return nil
                }
            }
            return event
        }
    }

    private func moveSelectionDown() {
        guard !results.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, results.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        scrollToKeepSelectionCentered()
        tableView.reloadData()
    }

    private func moveSelectionUp() {
        guard !results.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        scrollToKeepSelectionCentered()
        tableView.reloadData()
    }

    /// 滚动表格使选中行尽量保持在可视区域中间
    private func scrollToKeepSelectionCentered() {
        let visibleRect = scrollView.contentView.bounds

        // 计算可视区域能显示多少行
        let visibleRows = Int(visibleRect.height / rowHeight)
        let middleOffset = visibleRows / 2

        // 计算目标滚动位置，使选中行在中间
        let targetRow = max(0, selectedIndex - middleOffset)
        let targetRect = tableView.rect(ofRow: targetRow)

        // 如果选中行在前几行，不需要居中（保持在顶部）
        if selectedIndex < middleOffset {
            tableView.scrollRowToVisible(0)
        }
        // 如果选中行在最后几行，不需要居中（保持在底部）
        else if selectedIndex >= results.count - middleOffset {
            tableView.scrollRowToVisible(results.count - 1)
        }
        // 否则滚动使选中行居中
        else {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetRect.origin.y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    /// 加载最近使用的应用
    private func loadRecentApps() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var apps: [SearchResult] = []

            // 获取最近使用的应用（通过 LSCopyApplicationURLsForBundleIdentifier 或扫描常用应用）
            let commonAppPaths = [
                "/Applications",
                "/System/Applications",
            ]

            // 获取最近打开的应用（通过 NSWorkspace）
            let runningApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { $0.bundleURL?.path }

            var addedPaths = Set<String>()

            // 优先添加正在运行的应用
            for path in runningApps.prefix(8) {
                guard !addedPaths.contains(path) else { continue }
                if let result = self?.createSearchResult(from: path) {
                    apps.append(result)
                    addedPaths.insert(path)
                }
            }

            // 如果不够，补充常用应用
            if apps.count < 8 {
                let defaultApps = [
                    "/System/Applications/Finder.app",
                    "/Applications/Safari.app",
                    "/System/Applications/System Preferences.app",
                    "/System/Applications/System Settings.app",
                    "/Applications/WeChat.app",
                    "/System/Applications/Notes.app",
                    "/System/Applications/Calendar.app",
                    "/System/Applications/Mail.app",
                ]

                for path in defaultApps {
                    guard apps.count < 8 else { break }
                    guard !addedPaths.contains(path) else { continue }
                    guard FileManager.default.fileExists(atPath: path) else { continue }

                    if let result = self?.createSearchResult(from: path) {
                        apps.append(result)
                        addedPaths.insert(path)
                    }
                }
            }

            DispatchQueue.main.async {
                self?.recentApps = apps

                // 如果是 Full 模式且当前没有搜索内容，显示最近应用
                let defaultWindowMode =
                    UserDefaults.standard.string(forKey: "defaultWindowMode") ?? "simple"
                if defaultWindowMode == "full" && self?.searchField.stringValue.isEmpty == true {
                    self?.results = apps
                    self?.isShowingRecents = true
                    self?.tableView.reloadData()
                    self?.updateVisibility()
                }
            }
        }
    }

    /// 从路径创建 SearchResult
    private func createSearchResult(from path: String) -> SearchResult? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let name = FileManager.default.displayName(atPath: path)
            .replacingOccurrences(of: ".app", with: "")
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)

        return SearchResult(
            name: name,
            path: path,
            icon: icon,
            isDirectory: true
        )
    }

    private func openSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        let item = results[selectedIndex]

        let url = URL(fileURLWithPath: item.path)
        NSWorkspace.shared.open(url)

        PanelManager.shared.hidePanel()
    }
}

// MARK: - NSTextFieldDelegate

extension SearchPanelViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue
        performSearch(query)
    }
}

// MARK: - NSTableViewDataSource

extension SearchPanelViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return results.count
    }
}

// MARK: - NSTableViewDelegate

extension SearchPanelViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        let identifier = NSUserInterfaceItemIdentifier("ResultCell")

        var cellView =
            tableView.makeView(withIdentifier: identifier, owner: self) as? ResultCellView
        if cellView == nil {
            cellView = ResultCellView()
            cellView?.identifier = identifier
        }

        let item = results[row]
        let isSelected = row == selectedIndex
        cellView?.configure(with: item, isSelected: isSelected)

        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row >= 0 && row < results.count {
            selectedIndex = row
            tableView.reloadData()
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return true
    }
}

// MARK: - Result Cell View

class ResultCellView: NSView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let backgroundView = NSView()

    // 用于切换 nameLabel 位置的约束
    private var nameLabelTopConstraint: NSLayoutConstraint!
    private var nameLabelCenterYConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        // Background
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 4
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        // Icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // Name
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        // Path
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pathLabel)

        // 创建两种布局约束
        nameLabelTopConstraint = nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6)
        nameLabelCenterYConstraint = nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            nameLabelTopConstraint,

            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
        ])
    }

    func configure(with item: SearchResult, isSelected: Bool) {
        iconView.image = item.icon
        nameLabel.stringValue = item.name

        // App 只显示名称（垂直居中、字体大），文件和文件夹显示路径
        let isApp = item.path.hasSuffix(".app")
        pathLabel.isHidden = isApp
        pathLabel.stringValue = isApp ? "" : item.path

        // 切换布局：App 垂直居中，其他顶部对齐
        if isApp {
            nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
            nameLabelTopConstraint.isActive = false
            nameLabelCenterYConstraint.isActive = true
        } else {
            nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
            nameLabelCenterYConstraint.isActive = false
            nameLabelTopConstraint.isActive = true
        }

        if isSelected {
            backgroundView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            nameLabel.textColor = .white
            pathLabel.textColor = .white.withAlphaComponent(0.8)
        } else {
            backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
            nameLabel.textColor = .labelColor
            pathLabel.textColor = .secondaryLabelColor
        }
    }
}
