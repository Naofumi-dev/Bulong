import Foundation

enum RecommendedModel: Equatable { case parakeetV2, parakeetV3, whisper }

enum ModelRecommendation {
    /// Which bundled model best fits the chosen dictation language.
    static func model(forLanguage code: String) -> RecommendedModel {
        switch code {
        case "en": return .parakeetV2
        case "es", "fr", "de", "it", "pt": return .parakeetV3
        default: return .whisper
        }
    }
}
