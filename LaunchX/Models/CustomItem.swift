import AppKit
import Foundation

/// 快捷键配置
struct HotKeyConfig: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 显示字符串（如 "⌥⌘V"）
    var displayString: String {
        HotKeyService.displayString(for: modifiers, keyCode: keyCode)
    }

    /// 唯一标识符（用于比较是否相同的快捷键）
    var identifier: String {
        "\(modifiers)-\(keyCode)"
    }
}

/// 自定义项目
struct CustomItem: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var path: String  // 应用/文件夹路径
    var alias: String?  // 别名（可选）
    var openHotKey: HotKeyConfig?  // 打开/执行快捷键
    var extensionHotKey: HotKeyConfig?  // 进入扩展快捷键（仅 IDE 支持）

    init(
        id: UUID = UUID(),
        path: String,
        alias: String? = nil,
        openHotKey: HotKeyConfig? = nil,
        extensionHotKey: HotKeyConfig? = nil
    ) {
        self.id = id
        self.path = path
        self.alias = alias
        self.openHotKey = openHotKey
        self.extensionHotKey = extensionHotKey
    }

    // MARK: - 计算属性

    /// 显示名称（从路径提取）
    var name: String {
        let url = URL(fileURLWithPath: path)
        var name = url.deletingPathExtension().lastPathComponent
        // 如果是 .app，移除扩展名
        if path.hasSuffix(".app") {
            name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        }
        return name
    }

    /// 是否为 IDE 应用
    var isIDE: Bool {
        IDEType.detect(from: path) != nil
    }

    /// IDE 类型（如果是 IDE）
    var ideType: IDEType? {
        IDEType.detect(from: path)
    }

    /// 是否为应用程序
    var isApp: Bool {
        path.hasSuffix(".app")
    }

    /// 是否为文件夹
    var isDirectory: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// 获取图标
    var icon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }

    /// 简化的显示路径
    var displayPath: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homeDir) {
            return "~" + String(path.dropFirst(homeDir.count))
        }
        return path
    }

    // MARK: - Equatable & Hashable

    static func == (lhs: CustomItem, rhs: CustomItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
