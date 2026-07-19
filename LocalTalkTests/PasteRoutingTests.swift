import XCTest
@testable import Bulong

@MainActor
final class PasteRoutingTests: XCTestCase {
    // A native, editable focus where the AX write lands: direct insert.
    func testNativeEditableAXWriteSucceedsInsertsDirectly() {
        let route = PasteService.insertionRoute(
            isNonEditable: false, isWebContent: false, axWriteSucceeded: true)
        XCTAssertEqual(route, .inserted)
    }

    // Native, editable, but the AX write fails (some Cocoa fields reject it):
    // fall back to Cmd-V rather than dropping the text.
    func testNativeEditableAXWriteFailsFallsBackToCmdV() {
        let route = PasteService.insertionRoute(
            isNonEditable: false, isWebContent: false, axWriteSucceeded: false)
        XCTAssertEqual(route, .fallBackToCmdV)
    }

    // The regression this guards: web content (browser / Electron) reports the
    // AX write as succeeding but silently drops it. Route MUST be Cmd-V, and the
    // AX write must NOT even be consulted (it would falsely say .inserted).
    func testWebContentUsesCmdVAndNeverConsultsAXWrite() {
        var axConsulted = false
        func axWrite() -> Bool { axConsulted = true; return true }  // would falsely claim success
        let route = PasteService.insertionRoute(
            isNonEditable: false, isWebContent: true, axWriteSucceeded: axWrite())
        XCTAssertEqual(route, .fallBackToCmdV)
        XCTAssertFalse(axConsulted, "web content must skip the AX write entirely")
    }

    // Positively non-text focus (button, slider, menu, image) is never pasted
    // into — takes precedence over both web and native paths.
    func testNonEditableFocusIsNeverPasted() {
        XCTAssertEqual(
            PasteService.insertionRoute(isNonEditable: true, isWebContent: false, axWriteSucceeded: true),
            .noEditableFocus)
        XCTAssertEqual(
            PasteService.insertionRoute(isNonEditable: true, isWebContent: true, axWriteSucceeded: true),
            .noEditableFocus)
    }
}
