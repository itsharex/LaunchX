import Carbon
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 别名与快捷键设置视图

struct AliasShortcutSettingsView: View {
    @StateObject private var viewModel = AliasShortcutViewModel()
    @State private var searchText = ""
    @State private var isDragTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索应用、扩展、文档、文件夹与别名...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)

                Spacer()

                // 添加按钮
                Button(action: { viewModel.showFilePicker() }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("添加应用或文件夹")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // 列表表头
            HStack(spacing: 0) {
                Text("名称")
                    .frame(width: 160, alignment: .leading)
                Spacer().frame(width: 20)
                Text("别名")
                    .frame(width: 80, alignment: .leading)
                Spacer()
                Text("打开/执行")
                    .frame(width: 100, alignment: .center)
                Text("进入扩展")
                    .frame(width: 100, alignment: .center)
                Spacer().frame(width: 40)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // 列表内容
            if viewModel.customItems.isEmpty {
                // 空状态
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // 自定义分类
                        DisclosureGroup(
                            isExpanded: $viewModel.customExpanded,
                            content: {
                                ForEach(filteredItems) { item in
                                    CustomItemRow(
                                        item: binding(for: item),
                                        viewModel: viewModel
                                    )
                                    Divider().padding(.leading, 16)
                                }
                            },
                            label: {
                                HStack {
                                    Text("自定义")
                                        .font(.headline)
                                    Text("(\(viewModel.customItems.count))")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        Divider()

                        // 系统命令（占位）
                        placeholderSection(title: "系统命令", description: "即将推出")

                        Divider()

                        // 网页直达（占位）
                        placeholderSection(title: "网页直达", description: "即将推出")

                        Divider()

                        // 实用工具（占位）
                        placeholderSection(title: "实用工具", description: "即将推出")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            viewModel.handleDrop(providers)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDragTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                .padding(4)
        )
    }

    // MARK: - 辅助视图

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "plus.square.dashed")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("拖拽应用或文件夹到此处")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("或点击右上角 + 按钮添加")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("添加项目") {
                viewModel.showFilePicker()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholderSection(title: String, description: String) -> some View {
        DisclosureGroup(
            content: {
                HStack {
                    Spacer()
                    Text(description)
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .padding(.vertical, 20)
                    Spacer()
                }
            },
            label: {
                Text(title)
                    .font(.headline)
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - 辅助方法

    private var filteredItems: [CustomItem] {
        if searchText.isEmpty {
            return viewModel.customItems
        }
        let lowercasedSearch = searchText.lowercased()
        return viewModel.customItems.filter { item in
            item.name.lowercased().contains(lowercasedSearch)
                || (item.alias?.lowercased().contains(lowercasedSearch) ?? false)
                || item.path.lowercased().contains(lowercasedSearch)
        }
    }

    private func binding(for item: CustomItem) -> Binding<CustomItem> {
        Binding(
            get: {
                viewModel.customItems.first { $0.id == item.id } ?? item
            },
            set: { newValue in
                viewModel.updateItem(newValue)
            }
        )
    }
}

// MARK: - 列表行组件

struct CustomItemRow: View {
    @Binding var item: CustomItem
    @ObservedObject var viewModel: AliasShortcutViewModel

    @State private var aliasText: String = ""
    @State private var showOpenHotKeyPopover = false
    @State private var showExtensionHotKeyPopover = false

    var body: some View {
        HStack(spacing: 0) {
            // 图标和名称
            HStack(spacing: 8) {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 24, height: 24)

                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 160, alignment: .leading)

            Spacer().frame(width: 20)

            // 别名输入
            TextField("别名", text: $aliasText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .onAppear {
                    aliasText = item.alias ?? ""
                }
                .onChange(of: aliasText) { _, newValue in
                    var updatedItem = item
                    updatedItem.alias = newValue.isEmpty ? nil : newValue
                    viewModel.updateItem(updatedItem)
                }

            Spacer()

            // 打开/执行快捷键
            HotKeyButton(
                hotKey: item.openHotKey,
                onTap: { showOpenHotKeyPopover = true }
            )
            .frame(width: 100)
            .popover(isPresented: $showOpenHotKeyPopover) {
                HotKeyRecorderPopover(
                    hotKey: Binding(
                        get: { item.openHotKey },
                        set: { newValue in
                            var updatedItem = item
                            updatedItem.openHotKey = newValue
                            viewModel.updateItem(updatedItem)
                        }
                    ),
                    itemId: item.id,
                    isPresented: $showOpenHotKeyPopover
                )
            }

            // 进入扩展快捷键
            if item.isIDE {
                HotKeyButton(
                    hotKey: item.extensionHotKey,
                    onTap: { showExtensionHotKeyPopover = true }
                )
                .frame(width: 100)
                .popover(isPresented: $showExtensionHotKeyPopover) {
                    HotKeyRecorderPopover(
                        hotKey: Binding(
                            get: { item.extensionHotKey },
                            set: { newValue in
                                var updatedItem = item
                                updatedItem.extensionHotKey = newValue
                                viewModel.updateItem(updatedItem)
                            }
                        ),
                        itemId: item.id,
                        isPresented: $showExtensionHotKeyPopover
                    )
                }
            } else {
                Text("-")
                    .foregroundColor(.secondary)
                    .frame(width: 100)
            }

            // 删除按钮
            Button(action: { viewModel.deleteItem(item) }) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .frame(width: 40)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

// MARK: - 快捷键按钮

struct HotKeyButton: View {
    let hotKey: HotKeyConfig?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if let hotKey = hotKey {
                HStack(spacing: 2) {
                    // 显示修饰键符号
                    ForEach(
                        HotKeyService.modifierSymbols(for: hotKey.modifiers), id: \.self
                    ) { symbol in
                        KeyCapView(text: symbol)
                    }
                    // 显示按键
                    KeyCapView(text: HotKeyService.keyString(for: hotKey.keyCode))
                }
            } else {
                Text("快捷键")
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - 按键帽视图

struct KeyCapView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(3)
    }
}

// MARK: - ViewModel

class AliasShortcutViewModel: ObservableObject {
    @Published var customItems: [CustomItem] = []
    @Published var customExpanded: Bool = true

    init() {
        loadConfig()
    }

    // MARK: - 配置加载和保存

    private func loadConfig() {
        let config = CustomItemsConfig.load()
        customItems = config.customItems
    }

    private func saveConfig() {
        var config = CustomItemsConfig.load()
        config.customItems = customItems
        config.save()

        // 重新加载快捷键
        HotKeyService.shared.reloadCustomHotKeys(from: config)
    }

    // MARK: - 项目操作

    func updateItem(_ item: CustomItem) {
        if let index = customItems.firstIndex(where: { $0.id == item.id }) {
            customItems[index] = item
            saveConfig()
        }
    }

    func deleteItem(_ item: CustomItem) {
        customItems.removeAll { $0.id == item.id }
        saveConfig()
    }

    func deleteItems(at offsets: IndexSet) {
        customItems.remove(atOffsets: offsets)
        saveConfig()
    }

    func addItem(path: String) {
        // 检查是否已存在
        guard !customItems.contains(where: { $0.path == path }) else { return }

        // 验证路径
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return }

        // 只允许 .app 或目录
        guard path.hasSuffix(".app") || isDir.boolValue else { return }

        let item = CustomItem(path: path)
        customItems.append(item)
        saveConfig()
    }

    // MARK: - 拖拽处理

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                    data, _ in
                    guard let data = data as? Data,
                        let url = URL(dataRepresentation: data, relativeTo: nil)
                    else { return }

                    DispatchQueue.main.async {
                        self.addItem(path: url.path)
                    }
                }
                handled = true
            }
        }

        return handled
    }

    // MARK: - 文件选择器

    func showFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application, .folder]
        panel.message = "选择要添加的应用或文件夹"
        panel.prompt = "添加"

        if panel.runModal() == .OK {
            for url in panel.urls {
                addItem(path: url.path)
            }
        }
    }

    // MARK: - 冲突检测

    func checkConflict(keyCode: UInt32, modifiers: UInt32, excludingItemId: UUID) -> String? {
        return HotKeyService.shared.checkConflict(
            keyCode: keyCode,
            modifiers: modifiers,
            excludingItemId: excludingItemId
        )
    }
}

// MARK: - Preview

#Preview {
    AliasShortcutSettingsView()
        .frame(width: 600, height: 400)
}
