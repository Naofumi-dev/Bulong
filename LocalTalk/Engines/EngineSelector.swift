import Foundation

enum ParakeetVersion: Equatable {
    case v2
    case v3
}

struct EngineRoute: Equatable {
    var engine: EngineID
    var parakeetVersion: ParakeetVersion?
}

enum EngineSelector {
    static let parakeetV3Languages: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
        "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
    ]

    static func route(language: String, task: DictationTask, override: EngineID?) -> EngineRoute {
        if task == .translate {
            return EngineRoute(engine: .whisperKit, parakeetVersion: nil)
        }

        if let override {
            if override == .parakeet && !parakeetV3Languages.contains(language) {
                return EngineRoute(engine: .whisperKit, parakeetVersion: nil)
            }

            return EngineRoute(
                engine: override,
                parakeetVersion: override == .parakeet ? (language == "en" ? .v2 : .v3) : nil
            )
        }

        if language == "en" {
            return EngineRoute(engine: .parakeet, parakeetVersion: .v2)
        }

        if parakeetV3Languages.contains(language) {
            return EngineRoute(engine: .parakeet, parakeetVersion: .v3)
        }

        return EngineRoute(engine: .whisperKit, parakeetVersion: nil)
    }
}
