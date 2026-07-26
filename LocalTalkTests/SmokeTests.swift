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
        for _ in 0..<240 { loudRoomQuiet = AudioService.adaptiveNormalize(raw: 0.45, floor: &floor, peak: &peak) }
        XCTAssertLessThan(loudRoomQuiet, 0.12, "the gate must adapt to the environment")
    }

    /// The bug the user reported three times: bursty conversation looked fine
    /// because word gaps reset the floor, but reading a passage aloud let the
    /// floor climb into the voice and the bars died while they were still
    /// talking. ~11.7 buffers/sec, so 12s of speech is ~140 buffers.
    func testMeterSurvivesSustainedSpeech() {
        var floor: Float = 0.45
        var peak: Float = 0.7
        for _ in 0..<24 { _ = AudioService.adaptiveNormalize(raw: 0.30, floor: &floor, peak: &peak) }

        var level: Float = 0
        for _ in 0..<140 { level = AudioService.adaptiveNormalize(raw: 0.62, floor: &floor, peak: &peak) }
        XCTAssertGreaterThan(level, 0.5, "the meter must still track a voice after 12s of continuous speech")
    }

    /// A cough or a door slam spikes the peak; the meter must not stay deadened
    /// for the rest of the sentence.
    func testMeterRecoversQuicklyFromALoudTransient() {
        var floor: Float = 0.45
        var peak: Float = 0.7
        for _ in 0..<24 { _ = AudioService.adaptiveNormalize(raw: 0.30, floor: &floor, peak: &peak) }
        var speech: Float = 0
        for _ in 0..<35 { speech = AudioService.adaptiveNormalize(raw: 0.62, floor: &floor, peak: &peak) }

        for _ in 0..<2 { _ = AudioService.adaptiveNormalize(raw: 1.0, floor: &floor, peak: &peak) }

        var recovered: Float = 0
        for _ in 0..<24 { recovered = AudioService.adaptiveNormalize(raw: 0.62, floor: &floor, peak: &peak) }
        XCTAssertGreaterThan(recovered, speech * 0.7,
                             "two seconds after a transient the meter must be back near its speech level")
    }
}
