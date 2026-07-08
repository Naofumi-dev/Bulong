import XCTest
@testable import Bulong

final class ModelRecommendationTests: XCTestCase {
    func testEnglishRecommendsParakeetV2() {
        XCTAssertEqual(ModelRecommendation.model(forLanguage: "en"), .parakeetV2)
    }

    func testEuropeanLanguagesRecommendParakeetV3() {
        for code in ["es", "fr", "de", "it", "pt"] {
            XCTAssertEqual(ModelRecommendation.model(forLanguage: code), .parakeetV3)
        }
    }

    func testOtherLanguagesRecommendWhisper() {
        for code in ["tl", "ja", "ko", "zh", "xx"] {
            XCTAssertEqual(ModelRecommendation.model(forLanguage: code), .whisper)
        }
    }
}
