import Foundation

enum DictationState: Equatable {
    case idle
    case recording(started: Date)
    case transcribing
    case inserting
    case failed(message: String)
}

enum EngineID: String, Codable, CaseIterable {
    case parakeet
    case whisperKit

    /// User-facing name — must match the model names shown in Settings.
    var displayName: String {
        switch self {
        case .parakeet: "Parakeet"
        case .whisperKit: "Whisper"
        }
    }
}

enum DictationTask: String, Codable {
    case transcribe
    case translate
}

enum HotkeyMode: String, Codable, CaseIterable {
    case toggle
    case pushToTalk
}

enum TriggerKind: String, Codable, CaseIterable {
    case combo          // the Carbon hotkey (⌃⌥Space etc.)
    case singleKey      // a single modifier key (user's choice), hold-or-tap
}

enum SingleKeyChoice: String, Codable, CaseIterable {
    case rightOption, rightCommand, rightShift, rightControl, fn
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case f13, f14, f15, f16, f17, f18, f19

    /// How the key is observed. Modifier keys only surface as flag changes
    /// (NSEvent monitor — needs Accessibility); regular keys like F8 register
    /// as zero-modifier Carbon hotkeys, which need no permissions at all.
    enum Kind: Equatable {
        case modifier(deviceMask: UInt)
        case key(keyCode: UInt32)
    }

    var kind: Kind {
        switch self {
        case .rightShift: .modifier(deviceMask: 0x04)     // NX_DEVICERSHIFTKEYMASK
        case .rightCommand: .modifier(deviceMask: 0x10)   // NX_DEVICERCMDKEYMASK
        case .rightControl: .modifier(deviceMask: 0x2000) // NX_DEVICERCTLKEYMASK
        case .rightOption: .modifier(deviceMask: 0x40)    // NX_DEVICERALTKEYMASK
        case .fn: .modifier(deviceMask: 0x800000)         // NSEvent.ModifierFlags.function
        case .f1: .key(keyCode: 122)
        case .f2: .key(keyCode: 120)
        case .f3: .key(keyCode: 99)
        case .f4: .key(keyCode: 118)
        case .f5: .key(keyCode: 96)
        case .f6: .key(keyCode: 97)
        case .f7: .key(keyCode: 98)
        case .f8: .key(keyCode: 100)
        case .f9: .key(keyCode: 101)
        case .f10: .key(keyCode: 109)
        case .f11: .key(keyCode: 103)
        case .f12: .key(keyCode: 111)
        case .f13: .key(keyCode: 105)
        case .f14: .key(keyCode: 107)
        case .f15: .key(keyCode: 113)
        case .f16: .key(keyCode: 106)
        case .f17: .key(keyCode: 64)
        case .f18: .key(keyCode: 79)
        case .f19: .key(keyCode: 80)
        }
    }

    var needsAccessibility: Bool {
        if case .modifier = kind { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .rightOption: "Right Option (⌥)"
        case .rightCommand: "Right Command (⌘)"
        case .rightShift: "Right Shift (⇧)"
        case .rightControl: "Right Control (⌃)"
        case .fn: "Fn / Globe"
        default: rawValue.uppercased()
        }
    }
}

enum HUDPosition: String, Codable, CaseIterable {
    case bottomCenter, topRight, nearNotch
    var label: String {
        switch self {
        case .bottomCenter: "Bottom center"
        case .topRight: "Top right"
        case .nearNotch: "Below the notch"
        }
    }
}

enum TranscriptionUpdate: Sendable, Equatable {
    case partial(String)
    case final(String)
}

enum InsertionResult: Equatable {
    case insertedDirectly
    case pastedViaCmdV
    case clipboardOnly(reason: String)
}

struct HotkeySpec: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = HotkeySpec(keyCode: 49, carbonModifiers: 0x0800 | 0x1000)

    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & 0x1000 != 0 { parts.append("⌃") }
        if carbonModifiers & 0x0800 != 0 { parts.append("⌥") }
        if carbonModifiers & 0x0200 != 0 { parts.append("⇧") }
        if carbonModifiers & 0x0100 != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Esc"
        default:
            let names: [UInt32: String] = [
                0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
                40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
                32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z", 29: "0", 18: "1", 19: "2", 20: "3",
                21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9"
            ]
            return names[keyCode] ?? "Key\(keyCode)"
        }
    }
}

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    var date: Date
    var appName: String
    var engine: EngineID
    var language: String
    var durationSeconds: Double
}
