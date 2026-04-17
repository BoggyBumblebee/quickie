import Carbon
import AppKit

struct GlobalHotKey: Equatable {
    static let defaultHotKey = GlobalHotKey(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(cmdKey | optionKey | controlKey)
    )

    let keyCode: UInt32
    let carbonModifiers: UInt32

    var displayName: String {
        HotKeyDisplayName.make(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init?(event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        guard !Self.modifierOnlyKeyCodes.contains(keyCode) else { return nil }

        let carbonModifiers = event.modifierFlags.carbonHotKeyModifiers
        let requiredModifiers = UInt32(cmdKey | controlKey | optionKey)
        guard carbonModifiers & requiredModifiers != 0 else { return nil }

        self.init(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    private static let modifierOnlyKeyCodes: Set<UInt32> = [
        UInt32(kVK_Command),
        UInt32(kVK_Shift),
        UInt32(kVK_CapsLock),
        UInt32(kVK_Option),
        UInt32(kVK_Control),
        UInt32(kVK_RightCommand),
        UInt32(kVK_RightShift),
        UInt32(kVK_RightOption),
        UInt32(kVK_RightControl),
        UInt32(kVK_Function)
    ]
}

enum HotKeyShortcut: String, CaseIterable, Identifiable {
    case optionCommandSpace
    case optionCommandN
    case shiftOptionCommandN
    case controlOptionCommandSpace
    case controlOptionCommandN

    static let defaultShortcut: HotKeyShortcut = .controlOptionCommandSpace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .optionCommandSpace:
            "⌥⌘Space"
        case .optionCommandN:
            "⌥⌘N"
        case .shiftOptionCommandN:
            "⇧⌥⌘N"
        case .controlOptionCommandSpace:
            "⌃⌥⌘Space"
        case .controlOptionCommandN:
            "⌃⌥⌘N"
        }
    }

    var keyCode: UInt32 {
        hotKey.keyCode
    }

    var carbonModifiers: UInt32 {
        hotKey.carbonModifiers
    }

    var hotKey: GlobalHotKey {
        switch self {
        case .optionCommandSpace, .optionCommandN:
            GlobalHotKey(keyCode: keyCodeForShortcut, carbonModifiers: UInt32(cmdKey | optionKey))
        case .shiftOptionCommandN:
            GlobalHotKey(keyCode: keyCodeForShortcut, carbonModifiers: UInt32(cmdKey | optionKey | shiftKey))
        case .controlOptionCommandSpace, .controlOptionCommandN:
            GlobalHotKey(keyCode: keyCodeForShortcut, carbonModifiers: UInt32(cmdKey | optionKey | controlKey))
        }
    }

    private var keyCodeForShortcut: UInt32 {
        switch self {
        case .optionCommandSpace, .controlOptionCommandSpace:
            UInt32(kVK_Space)
        case .optionCommandN, .shiftOptionCommandN, .controlOptionCommandN:
            UInt32(kVK_ANSI_N)
        }
    }

    static func shortcut(rawValue: String) -> HotKeyShortcut {
        HotKeyShortcut(rawValue: rawValue) ?? defaultShortcut
    }
}

enum HotKeySettings {
    static let enabledKey = "GlobalHotKey.enabled"
    static let keyCodeKey = "GlobalHotKey.keyCode"
    static let modifiersKey = "GlobalHotKey.modifiers"
    static let registrationStatusKey = "GlobalHotKey.registrationStatus"
    static let shortcutKey = "GlobalHotKey.shortcut"
    private static let migratedDefaultKey = "GlobalHotKey.migratedDefaultToControlOptionCommandSpace"
    private static let migratedPresetKey = "GlobalHotKey.migratedPresetToKeyCode"

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            enabledKey: true,
            keyCodeKey: Int(GlobalHotKey.defaultHotKey.keyCode),
            modifiersKey: Int(GlobalHotKey.defaultHotKey.carbonModifiers),
            registrationStatusKey: Int(noErr),
            shortcutKey: HotKeyShortcut.defaultShortcut.rawValue
        ])

        if !defaults.bool(forKey: migratedPresetKey) {
            if let rawShortcut = defaults.string(forKey: shortcutKey),
               let legacyShortcut = HotKeyShortcut(rawValue: rawShortcut) {
                let migratedHotKey = legacyShortcut == .optionCommandSpace
                    ? GlobalHotKey.defaultHotKey
                    : legacyShortcut.hotKey

                defaults.set(Int(migratedHotKey.keyCode), forKey: keyCodeKey)
                defaults.set(Int(migratedHotKey.carbonModifiers), forKey: modifiersKey)
            }

            defaults.set(true, forKey: migratedPresetKey)
            defaults.set(true, forKey: migratedDefaultKey)
            defaults.synchronize()
        }
    }

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func selectedHotKey(_ defaults: UserDefaults = .standard) -> GlobalHotKey {
        GlobalHotKey(
            keyCode: UInt32(defaults.integer(forKey: keyCodeKey)),
            carbonModifiers: UInt32(defaults.integer(forKey: modifiersKey))
        )
    }

    static func registrationStatus(_ defaults: UserDefaults = .standard) -> OSStatus {
        OSStatus(defaults.integer(forKey: registrationStatusKey))
    }

    static func setRegistrationStatus(_ status: OSStatus, defaults: UserDefaults = .standard) {
        guard registrationStatus(defaults) != status else { return }
        defaults.set(Int(status), forKey: registrationStatusKey)
        defaults.synchronize()
    }
}

enum HotKeyRegistrationError {
    static func message(for status: OSStatus) -> String {
        let details: String

        switch status {
        case OSStatus(eventHotKeyExistsErr):
            details = "eventHotKeyExistsErr: the shortcut is already in use by macOS or another app."
        case OSStatus(eventHotKeyInvalidErr):
            details = "eventHotKeyInvalidErr: the shortcut registration request was invalid."
        case OSStatus(paramErr):
            details = "paramErr: Quickie sent invalid shortcut parameters."
        default:
            details = "Unknown Carbon hot key registration failure."
        }

        return "Shortcut registration failed (\(details) OSStatus \(status))."
    }
}

private enum HotKeyDisplayName {
    static func make(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        [
            carbonModifiers & UInt32(controlKey) != 0 ? "⌃" : nil,
            carbonModifiers & UInt32(optionKey) != 0 ? "⌥" : nil,
            carbonModifiers & UInt32(shiftKey) != 0 ? "⇧" : nil,
            carbonModifiers & UInt32(cmdKey) != 0 ? "⌘" : nil,
            keyName(for: keyCode)
        ]
        .compactMap { $0 }
        .joined()
    }

    private static func keyName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "Forward Delete",
        UInt32(kVK_Home): "Home",
        UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "Page Up",
        UInt32(kVK_PageDown): "Page Down",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13",
        UInt32(kVK_F14): "F14",
        UInt32(kVK_F15): "F15",
        UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17",
        UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19",
        UInt32(kVK_F20): "F20"
    ]
}

private extension NSEvent.ModifierFlags {
    var carbonHotKeyModifiers: UInt32 {
        var carbonModifiers: UInt32 = 0

        if contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }

        if contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }

        if contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }

        if contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }

        return carbonModifiers
    }
}
