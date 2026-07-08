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
