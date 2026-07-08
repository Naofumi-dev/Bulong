import XCTest
@testable import Bulong

final class TrialClockTests: XCTestCase {
    private var defaults: UserDefaults!
    private var fileURL: URL!
    private let day: TimeInterval = 86_400

    override func setUp() {
        defaults = UserDefaults(suiteName: "TrialClockTests")!
        defaults.removePersistentDomain(forName: "TrialClockTests")
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trial-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: fileURL) }

    func testFreshStartGives14() {
        let start = Date()
        let clock = TrialClock(defaults: defaults, fileURL: fileURL, trialDays: 14)
        XCTAssertEqual(clock.daysLeft(now: start), 14)
    }
    func testCountsDown() {
        let start = Date()
        let clock = TrialClock(defaults: defaults, fileURL: fileURL, trialDays: 14)
        _ = clock.daysLeft(now: start)              // establishes start
        XCTAssertEqual(clock.daysLeft(now: start.addingTimeInterval(5 * day)), 9)
        XCTAssertEqual(clock.daysLeft(now: start.addingTimeInterval(14 * day)), 0)
        XCTAssertEqual(clock.daysLeft(now: start.addingTimeInterval(20 * day)), 0)  // clamped
    }
    func testEarliestStoreWins() {
        let old = Date().addingTimeInterval(-10 * day)
        // Only the FILE has an old start; defaults empty. A fresh clock must adopt the old start.
        try! ISO8601DateFormatter().string(from: old).write(to: fileURL, atomically: true, encoding: .utf8)
        let clock = TrialClock(defaults: defaults, fileURL: fileURL, trialDays: 14)
        XCTAssertEqual(clock.daysLeft(now: Date()), 4)   // 14 - 10
    }
    func testNoNegativeCreditOnClockRollback() {
        let start = Date()
        let clock = TrialClock(defaults: defaults, fileURL: fileURL, trialDays: 14)
        _ = clock.daysLeft(now: start)
        // now earlier than start -> never MORE than 14, never negative days used
        XCTAssertEqual(clock.daysLeft(now: start.addingTimeInterval(-5 * day)), 14)
    }
}
