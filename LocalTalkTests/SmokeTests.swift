import XCTest
@testable import LocalTalk

final class SmokeTests: XCTestCase {
    func testThemeAccentExists() {
        XCTAssertNotNil(Theme.accent)
    }
}
