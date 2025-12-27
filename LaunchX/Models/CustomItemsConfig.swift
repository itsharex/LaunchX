import Foundation

/// 自定义项目配置管理
struct CustomItemsConfig: Codable {
    /// 自定义项目列表
    var customItems: [CustomItem] = []

    // 后续扩展预留
    // var systemCommands: [SystemCommand] = []
    // var webLinks: [WebLink] = []
    // var utilities: [Utility] = []

    // MARK: - 持久化

    private static let configKey = "CustomItemsConfig"

    /// 从 UserDefaults 加载配置
    static func load() -> CustomItemsConfig {
        guard let data = UserDefaults.standard.data(forKey: configKey),
            let config = try? JSONDecoder().decode(CustomItemsConfig.self, from: data)
        else {
            return CustomItemsConfig()
        }
        return config
    }

    /// 保存配置到 UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: CustomItemsConfig.configKey)
            // 发送配置变化通知
            NotificationCenter.default.post(name: .customItemsConfigDidChange, object: nil)
        }
    }

    /// 重置配置
    static func reset() {
        UserDefaults.standard.removeObject(forKey: configKey)
        NotificationCenter.default.post(name: .customItemsConfigDidChange, object: nil)
    }

    // MARK: - 辅助方法

    /// 获取别名映射表（alias -> path）
    func aliasMap() -> [String: String] {
        var map: [String: String] = [:]
        for item in customItems {
            if let alias = item.alias, !alias.isEmpty {
                map[alias.lowercased()] = item.path
            }
        }
        return map
    }

    /// 获取所有已配置的快捷键
    /// - Returns: 元组数组 (快捷键配置, 项目ID, 是否为进入扩展快捷键)
    func allHotKeys() -> [(config: HotKeyConfig, itemId: UUID, isExtension: Bool)] {
        var hotKeys: [(HotKeyConfig, UUID, Bool)] = []
        for item in customItems {
            if let openKey = item.openHotKey {
                hotKeys.append((openKey, item.id, false))
            }
            if let extKey = item.extensionHotKey {
                hotKeys.append((extKey, item.id, true))
            }
        }
        return hotKeys
    }

    /// 检查快捷键是否已被使用
    /// - Parameters:
    ///   - keyCode: 按键代码
    ///   - modifiers: 修饰键
    ///   - excludingItemId: 排除的项目 ID（用于编辑时排除自身）
    /// - Returns: 冲突的项目名称，nil 表示无冲突
    func checkHotKeyConflict(
        keyCode: UInt32, modifiers: UInt32, excludingItemId: UUID? = nil
    ) -> String? {
        for item in customItems {
            if let excludeId = excludingItemId, item.id == excludeId {
                continue
            }
            if let openKey = item.openHotKey,
                openKey.keyCode == keyCode && openKey.modifiers == modifiers
            {
                return "\(item.name) (打开)"
            }
            if let extKey = item.extensionHotKey,
                extKey.keyCode == keyCode && extKey.modifiers == modifiers
            {
                return "\(item.name) (进入扩展)"
            }
        }
        return nil
    }

    /// 根据 ID 查找项目
    func item(byId id: UUID) -> CustomItem? {
        customItems.first { $0.id == id }
    }

    /// 根据路径查找项目
    func item(byPath path: String) -> CustomItem? {
        customItems.first { $0.path == path }
    }

    // MARK: - 增删改

    /// 添加自定义项目
    mutating func addItem(_ item: CustomItem) {
        // 检查是否已存在相同路径的项目
        guard !customItems.contains(where: { $0.path == item.path }) else { return }
        customItems.append(item)
    }

    /// 更新自定义项目
    mutating func updateItem(_ item: CustomItem) {
        if let index = customItems.firstIndex(where: { $0.id == item.id }) {
            customItems[index] = item
        }
    }

    /// 删除自定义项目
    mutating func removeItem(byId id: UUID) {
        customItems.removeAll { $0.id == id }
    }

    /// 删除多个自定义项目
    mutating func removeItems(at offsets: IndexSet) {
        // 手动实现 remove(atOffsets:) 以避免依赖 SwiftUI
        let indicesToRemove = offsets.sorted(by: >)
        for index in indicesToRemove {
            customItems.remove(at: index)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// 自定义项目配置变化通知
    static let customItemsConfigDidChange = Notification.Name("customItemsConfigDidChange")

    /// 直接进入 IDE 模式通知（用于快捷键触发）
    static let enterIDEModeDirectly = Notification.Name("enterIDEModeDirectly")
    static let enterWebLinkQueryModeDirectly = Notification.Name("enterWebLinkQueryModeDirectly")
}
