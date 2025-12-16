import Carbon
import Cocoa

// C-convention callback function for the event handler
private func globalHotKeyHandler(
    nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    return HotKeyService.shared.handleEvent(event)
}

class HotKeyService {
    static let shared = HotKeyService()

    // Callback to be executed when hotkey is pressed
    var onHotKeyPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private let hotKeySignature = "LnHX"  // Unique signature for our app
    private let hotKeyId: UInt32 = 1

    private init() {}

    func setupGlobalHotKey() {
        // 1. Register the Event Handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            nil,
            nil)

        if status != noErr {
            print("Error installing event handler: \(status)")
            return
        }

        // 2. Register the HotKey (Option + Space)
        // kVK_Space = 0x31 (49)
        // optionKey = 1 << 11 (2048)
        let keyCode = UInt32(kVK_Space)
        let modifiers = UInt32(optionKey)

        let hotKeyID = EventHotKeyID(signature: OSType(be32(hotKeySignature)), id: hotKeyId)

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef)

        if registerStatus != noErr {
            print("Error registering hotkey: \(registerStatus)")
        } else {
            print("Global HotKey (Option + Space) registered successfully.")
        }
    }

    // Internal handler called by the C function
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
            &hotKeyID)

        if error == noErr {
            // Verify signature and ID
            if hotKeyID.signature == OSType(be32(hotKeySignature)) && hotKeyID.id == hotKeyId {
                DispatchQueue.main.async {
                    self.onHotKeyPressed?()
                }
                return noErr
            }
        }

        return OSStatus(eventNotHandledErr)
    }

    // Helper to convert 4-char string to OSType (UInt32)
    private func be32(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for char in string.utf8 {
            result = result << 8 + UInt32(char)
        }
        return result
    }

    deinit {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}
