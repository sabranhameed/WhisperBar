import AppKit
import Carbon.HIToolbox

// MARK: - Recording Mode

enum RecordingMode: String, Codable, CaseIterable {
    case toggle     = "toggle"
    case pushToTalk = "pushToTalk"

    var displayName: String {
        switch self {
        case .toggle:     return "Toggle (press once to start, press again to stop)"
        case .pushToTalk: return "Push-to-Talk (hold key while speaking)"
        }
    }
}

// MARK: - Key Combo

/// Represents a keyboard shortcut: one non-modifier key + one or more modifier keys.
struct KeyCombo: Codable, Equatable, Hashable {

    var keyCode:   Int   // Virtual key code (kVK_* constants)
    var modifiers: Int   // NSEvent.ModifierFlags rawValue (device-independent mask)

    // MARK: Defaults

    static let defaultToggle     = KeyCombo(keyCode: kVK_Space,       modifiers: modifierRaw([.command, .shift]))
    static let defaultPushToTalk = KeyCombo(keyCode: kVK_Space,       modifiers: modifierRaw([.command, .option]))
    static let empty             = KeyCombo(keyCode: 0,                modifiers: 0)

    // MARK: Helpers

    static func modifierRaw(_ flags: [NSEvent.ModifierFlags]) -> Int {
        Int(flags.reduce(NSEvent.ModifierFlags()) { $0.union($1) }.rawValue)
    }

    var nsModifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(modifiers))
    }

    /// Carbon modifier bits used by RegisterEventHotKey
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        let flags = nsModifiers
        if flags.contains(.command)  { result |= UInt32(cmdKey)     }
        if flags.contains(.option)   { result |= UInt32(optionKey)  }
        if flags.contains(.shift)    { result |= UInt32(shiftKey)   }
        if flags.contains(.control)  { result |= UInt32(controlKey) }
        return result
    }

    func matches(event: NSEvent) -> Bool {
        let eventFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let ourFlags   = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        return Int(event.keyCode) == keyCode && eventFlags == ourFlags
    }

    // MARK: Display

    var displayString: String {
        guard keyCode != 0 || modifiers != 0 else { return "Not set" }
        var parts: [String] = []
        let flags = nsModifiers
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for code: Int) -> String {
        switch code {
        // Whitespace / control
        case kVK_Space:             return "Space"
        case kVK_Return:            return "Return"
        case kVK_Tab:               return "Tab"
        case kVK_Delete:            return "Delete"
        case kVK_Escape:            return "Esc"
        case kVK_ForwardDelete:     return "Fwd⌫"
        // Function keys
        case kVK_F1:                return "F1"
        case kVK_F2:                return "F2"
        case kVK_F3:                return "F3"
        case kVK_F4:                return "F4"
        case kVK_F5:                return "F5"
        case kVK_F6:                return "F6"
        case kVK_F7:                return "F7"
        case kVK_F8:                return "F8"
        case kVK_F9:                return "F9"
        case kVK_F10:               return "F10"
        case kVK_F11:               return "F11"
        case kVK_F12:               return "F12"
        // Alphabet
        case kVK_ANSI_A:            return "A"
        case kVK_ANSI_B:            return "B"
        case kVK_ANSI_C:            return "C"
        case kVK_ANSI_D:            return "D"
        case kVK_ANSI_E:            return "E"
        case kVK_ANSI_F:            return "F"
        case kVK_ANSI_G:            return "G"
        case kVK_ANSI_H:            return "H"
        case kVK_ANSI_I:            return "I"
        case kVK_ANSI_J:            return "J"
        case kVK_ANSI_K:            return "K"
        case kVK_ANSI_L:            return "L"
        case kVK_ANSI_M:            return "M"
        case kVK_ANSI_N:            return "N"
        case kVK_ANSI_O:            return "O"
        case kVK_ANSI_P:            return "P"
        case kVK_ANSI_Q:            return "Q"
        case kVK_ANSI_R:            return "R"
        case kVK_ANSI_S:            return "S"
        case kVK_ANSI_T:            return "T"
        case kVK_ANSI_U:            return "U"
        case kVK_ANSI_V:            return "V"
        case kVK_ANSI_W:            return "W"
        case kVK_ANSI_X:            return "X"
        case kVK_ANSI_Y:            return "Y"
        case kVK_ANSI_Z:            return "Z"
        // Digits
        case kVK_ANSI_0:            return "0"
        case kVK_ANSI_1:            return "1"
        case kVK_ANSI_2:            return "2"
        case kVK_ANSI_3:            return "3"
        case kVK_ANSI_4:            return "4"
        case kVK_ANSI_5:            return "5"
        case kVK_ANSI_6:            return "6"
        case kVK_ANSI_7:            return "7"
        case kVK_ANSI_8:            return "8"
        case kVK_ANSI_9:            return "9"
        default:                    return "Key(\(code))"
        }
    }
}

// MARK: - UserDefaults helpers

extension UserDefaults {
    func keyCombo(forKey key: String) -> KeyCombo? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }
    func set(_ combo: KeyCombo, forKey key: String) {
        let data = try? JSONEncoder().encode(combo)
        set(data, forKey: key)
    }
}
