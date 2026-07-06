import XCTest
@testable import LocalTalk

final class EngineSelectorTests: XCTestCase {
    func testEnglishTranscribeUsesParakeetV2() {
        let route = EngineSelector.route(language: "en", task: .transcribe, override: nil)
        XCTAssertEqual(route.engine, .parakeet)
        XCTAssertEqual(route.parakeetVersion, .v2)
    }

    func testEuropeanLanguageUsesParakeetV3() {
        let route = EngineSelector.route(language: "de", task: .transcribe, override: nil)
        XCTAssertEqual(route.engine, .parakeet)
        XCTAssertEqual(route.parakeetVersion, .v3)
    }

    func testTagalogFallsBackToWhisperKit() {
        let route = EngineSelector.route(language: "tl", task: .transcribe, override: nil)
        XCTAssertEqual(route.engine, .whisperKit)
    }

    func testTranslateAlwaysUsesWhisperKit() {
        let route = EngineSelector.route(language: "en", task: .translate, override: nil)
        XCTAssertEqual(route.engine, .whisperKit)
    }

    func testUserOverrideWins() {
        let route = EngineSelector.route(language: "en", task: .transcribe, override: .whisperKit)
        XCTAssertEqual(route.engine, .whisperKit)
    }

    func testOverrideCannotBreakTranslate() {
        let route = EngineSelector.route(language: "en", task: .translate, override: .parakeet)
        XCTAssertEqual(route.engine, .whisperKit)
    }
}
