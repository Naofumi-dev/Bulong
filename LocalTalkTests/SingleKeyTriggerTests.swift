import XCTest
@testable import Bulong

final class SingleKeyTriggerTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testTapStartsAndStaysRecording() {
        var trg = SingleKeyTrigger(tapThreshold: 0.25)
        XCTAssertEqual(trg.keyDown(at: at(0)), .start)     // press
        XCTAssertEqual(trg.keyUp(at: at(0.1)), .none)      // quick release = tap-to-start, keep recording
        XCTAssertTrue(trg.isRecording)
    }

    func testSecondTapStops() {
        var trg = SingleKeyTrigger(tapThreshold: 0.25)
        _ = trg.keyDown(at: at(0)); _ = trg.keyUp(at: at(0.1))   // tap → recording
        XCTAssertEqual(trg.keyDown(at: at(1.0)), .none)          // second press (during toggle session)
        XCTAssertEqual(trg.keyUp(at: at(1.1)), .stop)            // release → stop
        XCTAssertFalse(trg.isRecording)
    }

    func testHoldIsPushToTalk() {
        var trg = SingleKeyTrigger(tapThreshold: 0.25)
        XCTAssertEqual(trg.keyDown(at: at(0)), .start)   // press starts
        XCTAssertEqual(trg.keyUp(at: at(0.9)), .stop)    // long hold → stop on release
        XCTAssertFalse(trg.isRecording)
    }

    func testResetClears() {
        var trg = SingleKeyTrigger(tapThreshold: 0.25)
        _ = trg.keyDown(at: at(0)); _ = trg.keyUp(at: at(0.1))  // recording
        trg.reset()
        XCTAssertFalse(trg.isRecording)
        XCTAssertEqual(trg.keyDown(at: at(2)), .start)          // fresh start after reset
    }
}
