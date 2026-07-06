import XCTest
@testable import Bulong

final class HotkeySpecTests: XCTestCase {
    func testDefaultIsCtrlOptSpace() {
        let spec = HotkeySpec.default
        XCTAssertEqual(spec.displayString, "⌃⌥Space")
    }

    func testDisplayStringForCmdShiftD() {
        let spec = HotkeySpec(keyCode: 2, carbonModifiers: 0x0100 | 0x0200)
        XCTAssertEqual(spec.displayString, "⇧⌘D")
    }

    func testRoundTripsThroughJSON() throws {
        let spec = HotkeySpec(keyCode: 9, carbonModifiers: 0x1000)
        let data = try JSONEncoder().encode(spec)
        let back = try JSONDecoder().decode(HotkeySpec.self, from: data)
        XCTAssertEqual(spec, back)
    }
}
