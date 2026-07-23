import Carbon.HIToolbox
import XCTest
@testable import Bulong

@MainActor
final class PasteRoutingTests: XCTestCase {
    // The synthesized Cmd-V must target whatever key produces "v" on the
    // CURRENT layout (9 is only the QWERTY position — it's "k" on Dvorak).
    func testKeyCodeForVResolvesOnCurrentLayout() {
        let code = PasteService.keyCodeForV()
        XCTAssertLessThan(code, 128)
        // On a QWERTY-family layout the answer is the classic 9; on anything
        // else it must simply be a valid resolved code (asserted above).
        let qwertyFamilies = ["com.apple.keylayout.US", "com.apple.keylayout.ABC",
                              "com.apple.keylayout.British", "com.apple.keylayout.Australian"]
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            if qwertyFamilies.contains(id) {
                XCTAssertEqual(code, 9)
            }
        }
    }

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
