import XCTest
@testable import Bulong

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "SettingsStoreTests")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests")
    }

    @MainActor func testDefaults() {
        let s = SettingsStore(defaults: defaults)
        XCTAssertEqual(s.language, "en")
        XCTAssertEqual(s.task, .transcribe)
        XCTAssertEqual(s.hotkeyMode, .toggle)
        XCTAssertEqual(s.hotkey, .default)
        XCTAssertNil(s.engineOverride)
        XCTAssertTrue(s.pasteAfterTranscription)
        XCTAssertFalse(s.hasCompletedOnboarding)
    }

    @MainActor func testPersistsAcrossInstances() {
        let s1 = SettingsStore(defaults: defaults)
        s1.language = "tl"
        s1.task = .translate
        s1.hotkey = HotkeySpec(keyCode: 2, carbonModifiers: 0x0100)
        s1.engineOverride = .whisperKit

        let s2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(s2.language, "tl")
        XCTAssertEqual(s2.task, .translate)
        XCTAssertEqual(s2.hotkey.keyCode, 2)
        XCTAssertEqual(s2.engineOverride, .whisperKit)
    }

    @MainActor func testHudPositionDefaultsToBottomCenterAndPersists() {
        let s1 = SettingsStore(defaults: defaults)
        XCTAssertEqual(s1.hudPosition, .bottomCenter)
        s1.hudPosition = .topRight
        let s2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(s2.hudPosition, .topRight)
    }

    @MainActor func testTriggerKindDefaultsComboAndPersists() {
        let s1 = SettingsStore(defaults: defaults)
        XCTAssertEqual(s1.triggerKind, .combo)
        s1.triggerKind = .rightOption
        let s2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(s2.triggerKind, .rightOption)
    }
}
