import XCTest
@testable import Bulong

final class SmokeTests: XCTestCase {
    func testThemeAccentExists() {
        XCTAssertNotNil(Theme.accent)
    }
}
