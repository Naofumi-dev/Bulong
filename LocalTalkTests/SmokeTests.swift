import XCTest
@testable import Bulong

final class SmokeTests: XCTestCase {
    func testThemeAccentExists() {
        XCTAssertNotNil(Theme.accent)
    }

    func testAdaptiveLevelNormalization() {
        var floor: Float = 0.45
        var peak: Float = 0.7

        // A quiet room (~0.30 on the dB scale): the floor adapts onto it and
        // the meter goes flat — room noise must NOT dance the bars.
        var quiet: Float = 1
        for _ in 0..<40 { quiet = AudioService.adaptiveNormalize(raw: 0.30, floor: &floor, peak: &peak) }
        XCTAssertLessThan(quiet, 0.1, "ambient noise must read as silence")

        // Speech (~0.62) against the adapted floor reads high.
        var speech: Float = 0
        for _ in 0..<10 { speech = AudioService.adaptiveNormalize(raw: 0.62, floor: &floor, peak: &peak) }
        XCTAssertGreaterThan(speech, 0.5, "speech must use the bars' upper range")

        // Louder room, different mic (~0.45 ambience): floor re-adapts and
        // that room's silence goes flat too — no fixed gate could do both.
        var loudRoomQuiet: Float = 1
        for _ in 0..<60 { loudRoomQuiet = AudioService.adaptiveNormalize(raw: 0.45, floor: &floor, peak: &peak) }
        XCTAssertLessThan(loudRoomQuiet, 0.12, "the gate must adapt to the environment")
    }
}
