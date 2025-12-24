import Carbon
import Cocoa
import Combine

// C-convention callback function for the event handler
private func globalHotKeyHandler(
    nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    return HotKeyService.shared.handleEvent(event)
}

class HotKeyService: ObservableObject {
    static let shared = HotKeyService()

    // MARK: - 主快捷键（打开搜索面板）

    /// 主快捷键触发回调
    var onHotKeyPressed: (() -> Void)?

    private var mainHotKeyRef: EventHotKeyRef?
    private let mainHotKeyId: UInt32 = 1

    /// 主快捷键的按键代码
    @Published var currentKeyCode: UInt32 = UInt32(kVK_Space)
    /// 主快捷键的修饰键
    @Published var currentModifiers: UInt32 = UInt32(optionKey)
    @Published var isEnabled: Bool = true

    // MARK: - 自定义快捷键

    /// 自定义快捷键触发回调 (itemId, isExtension)
    var onCustomHotKeyPressed: ((UUID, Bool) -> Void)?

    /// 自定义快捷键引用: hotKeyId -> EventHotKeyRef
    private var customHotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    /// 自定义快捷键动作: hotKeyId -> (itemId, isExtension)
    private var customHotKeyActions: [UInt32: (UUID, Bool)] = [:]
    /// 快捷键配置缓存: hotKeyId -> HotKeyConfig（用于冲突检测）
    private var customHotKeyConfigs: [UInt32: HotKeyConfig] = [:]
    /// 下一个可用的快捷键 ID（从 100 开始，避免与主快捷键冲突）
    private var nextCustomHotKeyId: UInt32 = 100

    // MARK: - 私有属性

    private let hotKeySignature: OSType
    private var eventHandlerRef: EventHandlerRef?

    // MARK: - 初始化

    private init() {
        // Create signature "LnHX"
        let c1 = UInt32(byteAt("L", 0))
        let c2 = UInt32(byteAt("n", 0))
        let c3 = UInt32(byteAt("H", 0))
        let c4 = UInt32(byteAt("X", 0))

        self.hotKeySignature = OSType((c1 << 24) | (c2 << 16) | (c3 << 8) | c4)
    }

    // MARK: - 主快捷键方法

    func setupGlobalHotKey() {
        // Install event handler only once
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            print("HotKeyService: Failed to install event handler. Status: \(status)")
            return
        }

        // Load saved key or use default (Option + Space)
        let savedKeyCode = UserDefaults.standard.object(forKey: "hotKeyKeyCode") as? Int
        let savedModifiers = UserDefaults.standard.object(forKey: "hotKeyModifiers") as? Int

        if let key = savedKeyCode, let mods = savedModifiers {
            registerMainHotKey(keyCode: UInt32(key), modifiers: UInt32(mods))
        } else {
            registerMainHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
        }
    }

    /// 注册主快捷键（打开搜索面板）
    func registerMainHotKey(keyCode: UInt32, modifiers: UInt32) {
        // Unregister existing if any
        if let ref = mainHotKeyRef {
            UnregisterEventHotKey(ref)
            mainHotKeyRef = nil
        }

        self.currentKeyCode = keyCode
        self.currentModifiers = modifiers

        // Save persistence
        UserDefaults.standard.set(Int(keyCode), forKey: "hotKeyKeyCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "hotKeyModifiers")

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: mainHotKeyId)

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &mainHotKeyRef
        )

        if registerStatus != noErr {
            print("HotKeyService: Failed to register main hotkey. Status: \(registerStatus)")
        } else {
            print("HotKeyService: Registered Main HotKey (Code: \(keyCode), Mods: \(modifiers))")
        }
    }

    /// 兼容旧的方法名
    func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        registerMainHotKey(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - 自定义快捷键方法

    /// 注册自定义快捷键
    /// - Parameters:
    ///   - keyCode: 按键代码
    ///   - modifiers: 修饰键
    ///   - itemId: 关联的项目 ID
    ///   - isExtension: 是否为"进入扩展"快捷键
    /// - Returns: 快捷键 ID，失败返回 nil
    @discardableResult
    func registerCustomHotKey(
        keyCode: UInt32, modifiers: UInt32, itemId: UUID, isExtension: Bool
    ) -> UInt32? {
        let hotKeyId = nextCustomHotKeyId
        nextCustomHotKeyId += 1

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: hotKeyId)
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            print(
                "HotKeyService: Failed to register custom hotkey. Status: \(status), KeyCode: \(keyCode), Mods: \(modifiers)"
            )
            return nil
        }

        customHotKeyRefs[hotKeyId] = hotKeyRef
        customHotKeyActions[hotKeyId] = (itemId, isExtension)
        customHotKeyConfigs[hotKeyId] = HotKeyConfig(keyCode: keyCode, modifiers: modifiers)

        print(
            "HotKeyService: Registered Custom HotKey (ID: \(hotKeyId), Code: \(keyCode), Mods: \(modifiers), Item: \(itemId), IsExt: \(isExtension))"
        )

        return hotKeyId
    }

    /// 注销自定义快捷键
    func unregisterCustomHotKey(hotKeyId: UInt32) {
        guard let ref = customHotKeyRefs[hotKeyId] else { return }

        UnregisterEventHotKey(ref)
        customHotKeyRefs.removeValue(forKey: hotKeyId)
        customHotKeyActions.removeValue(forKey: hotKeyId)
        customHotKeyConfigs.removeValue(forKey: hotKeyId)

        print("HotKeyService: Unregistered Custom HotKey (ID: \(hotKeyId))")
    }

    /// 注销所有自定义快捷键
    func unregisterAllCustomHotKeys() {
        for (hotKeyId, ref) in customHotKeyRefs {
            UnregisterEventHotKey(ref)
            print("HotKeyService: Unregistered Custom HotKey (ID: \(hotKeyId))")
        }
        customHotKeyRefs.removeAll()
        customHotKeyActions.removeAll()
        customHotKeyConfigs.removeAll()
    }

    /// 从配置重新加载所有自定义快捷键
    func reloadCustomHotKeys(from config: CustomItemsConfig) {
        // 先注销所有现有的自定义快捷键
        unregisterAllCustomHotKeys()

        // 重新注册
        for item in config.customItems {
            if let openKey = item.openHotKey {
                registerCustomHotKey(
                    keyCode: openKey.keyCode,
                    modifiers: openKey.modifiers,
                    itemId: item.id,
                    isExtension: false
                )
            }
            if let extKey = item.extensionHotKey {
                registerCustomHotKey(
                    keyCode: extKey.keyCode,
                    modifiers: extKey.modifiers,
                    itemId: item.id,
                    isExtension: true
                )
            }
        }

        print("HotKeyService: Reloaded \(customHotKeyRefs.count) custom hotkeys")
    }

    // MARK: - 冲突检测

    /// 检查快捷键是否冲突
    /// - Parameters:
    ///   - keyCode: 按键代码
    ///   - modifiers: 修饰键
    ///   - excludingItemId: 排除的项目 ID（用于编辑时排除自身）
    /// - Returns: 冲突的描述，nil 表示无冲突
    func checkConflict(keyCode: UInt32, modifiers: UInt32, excludingItemId: UUID? = nil) -> String?
    {
        // 检查与主快捷键的冲突
        if keyCode == currentKeyCode && modifiers == currentModifiers {
            return "打开搜索"
        }

        // 检查与自定义快捷键的冲突
        for (hotKeyId, config) in customHotKeyConfigs {
            if config.keyCode == keyCode && config.modifiers == modifiers {
                if let action = customHotKeyActions[hotKeyId] {
                    let itemId = action.0
                    let isExtension = action.1

                    // 如果是同一个项目，跳过
                    if let excludeId = excludingItemId, itemId == excludeId {
                        continue
                    }

                    // 从配置中获取项目名称
                    let itemsConfig = CustomItemsConfig.load()
                    if let item = itemsConfig.item(byId: itemId) {
                        let suffix = isExtension ? " (进入扩展)" : " (打开)"
                        return item.name + suffix
                    }
                }
            }
        }

        return nil
    }

    // MARK: - 事件处理

    /// 内部事件处理方法
    fileprivate func handleEvent(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let error = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        if error == noErr && hotKeyID.signature == hotKeySignature {
            // 检查是否为主快捷键
            if hotKeyID.id == mainHotKeyId {
                DispatchQueue.main.async { [weak self] in
                    self?.onHotKeyPressed?()
                }
                return noErr
            }

            // 检查是否为自定义快捷键
            if let action = customHotKeyActions[hotKeyID.id] {
                DispatchQueue.main.async { [weak self] in
                    self?.onCustomHotKeyPressed?(action.0, action.1)
                }
                return noErr
            }
        }

        return OSStatus(eventNotHandledErr)
    }

    deinit {
        // 注销主快捷键
        if let ref = mainHotKeyRef {
            UnregisterEventHotKey(ref)
        }

        // 注销所有自定义快捷键
        for (_, ref) in customHotKeyRefs {
            UnregisterEventHotKey(ref)
        }

        // 移除事件处理程序
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}

// MARK: - Helpers

private func byteAt(_ string: String, _ index: Int) -> UInt8 {
    let array = Array(string.utf8)
    guard index < array.count else { return 0 }
    return array[index]
}

extension HotKeyService {
    // Helper to convert NSEvent.ModifierFlags to Carbon modifiers
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonFlags |= UInt32(optionKey) }
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
        return carbonFlags
    }

    // Helper to convert Carbon modifiers to string for display
    static func displayString(for modifiers: UInt32, keyCode: UInt32) -> String {
        var string = ""
        if modifiers & UInt32(controlKey) != 0 { string += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { string += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { string += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { string += "⌘" }

        string += keyString(for: keyCode)
        return string
    }

    /// 获取修饰键的符号数组
    static func modifierSymbols(for modifiers: UInt32) -> [String] {
        var symbols: [String] = []
        if modifiers & UInt32(controlKey) != 0 { symbols.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { symbols.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { symbols.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { symbols.append("⌘") }
        return symbols
    }

    static func keyString(for keyCode: UInt32) -> String {
        // TISInputSource would be more accurate for localized keyboards,
        // but this manual mapping covers standard US ANSI layout.
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "Esc"

        // ANSI Letters
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"

        // ANSI Numbers
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"

        // Common Symbols
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"

        // Function Keys
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"

        default: return "?"
        }
    }
}
