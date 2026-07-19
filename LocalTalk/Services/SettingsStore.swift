import Foundation
import Observation

@MainActor @Observable
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.language = defaults.string(forKey: "language") ?? "en"
        self.task = DictationTask(rawValue: defaults.string(forKey: "task") ?? "") ?? .transcribe
        self.hotkeyMode = HotkeyMode(rawValue: defaults.string(forKey: "hotkeyMode") ?? "") ?? .toggle
        // Single key is the default trigger; the combo stays as a legacy
        // option (existing users who stored an explicit choice keep it).
        self.triggerKind = TriggerKind(rawValue: defaults.string(forKey: "triggerKind") ?? "") ?? .singleKey
        self.singleKeyChoice = SingleKeyChoice(rawValue: defaults.string(forKey: "singleKeyChoice") ?? "") ?? .rightOption
        self.pasteAfterTranscription = defaults.object(forKey: "pasteAfterTranscription") as? Bool ?? true
        self.playSounds = defaults.object(forKey: "playSounds") as? Bool ?? false
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.hudPosition = HUDPosition(rawValue: defaults.string(forKey: "hudPosition") ?? "") ?? .bottomCenter
        if let data = defaults.data(forKey: "hotkey"),
           let spec = try? JSONDecoder().decode(HotkeySpec.self, from: data) {
            self.hotkey = spec
        } else {
            self.hotkey = .default
        }
        if let raw = defaults.string(forKey: "engineOverride") {
            self.engineOverride = EngineID(rawValue: raw)
        } else {
            self.engineOverride = nil
        }
    }

    var language: String {
        didSet { defaults.set(language, forKey: "language") }
    }

    var task: DictationTask {
        didSet { defaults.set(task.rawValue, forKey: "task") }
    }

    var hotkeyMode: HotkeyMode {
        didSet { defaults.set(hotkeyMode.rawValue, forKey: "hotkeyMode") }
    }

    var triggerKind: TriggerKind {
        didSet { defaults.set(triggerKind.rawValue, forKey: "triggerKind") }
    }

    var singleKeyChoice: SingleKeyChoice {
        didSet { defaults.set(singleKeyChoice.rawValue, forKey: "singleKeyChoice") }
    }

    var hotkey: HotkeySpec {
        didSet { defaults.set(try? JSONEncoder().encode(hotkey), forKey: "hotkey") }
    }

    var engineOverride: EngineID? {
        didSet { defaults.set(engineOverride?.rawValue, forKey: "engineOverride") }
    }

    var pasteAfterTranscription: Bool {
        didSet { defaults.set(pasteAfterTranscription, forKey: "pasteAfterTranscription") }
    }

    var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: "playSounds") }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var hudPosition: HUDPosition {
        didSet { defaults.set(hudPosition.rawValue, forKey: "hudPosition") }
    }
}
