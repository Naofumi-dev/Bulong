import XCTest
import CryptoKit
@testable import Bulong

@MainActor
final class LicenseServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var trialFile: URL!
    private let day: TimeInterval = 86_400

    override func setUp() {
        defaults = UserDefaults(suiteName: "LicenseServiceTests")!
        defaults.removePersistentDomain(forName: "LicenseServiceTests")
        trialFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("trial-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: trialFile) }

    private func verifier() -> LicenseVerifier {
        let pub = try! Curve25519.Signing.PublicKey(
            rawRepresentation: Data(base64Encoded: LicenseFixtures.testPublicKeyB64)!)
        return LicenseVerifier(publicKey: pub)
    }
    private func service(now: Date = Date()) -> LicenseService {
        LicenseService(verifier: verifier(),
                       clock: TrialClock(defaults: defaults, fileURL: trialFile, trialDays: 14),
                       defaults: defaults, now: { now })
    }

    func testFreshInstallIsTrial() {
        let s = service()
        guard case .trial(let d) = s.state else { return XCTFail("expected trial") }
        XCTAssertEqual(d, 14)
        XCTAssertTrue(s.canDictate)
    }
    func testExpiredTrialBlocksDictation() {
        // seed an old trial start directly
        defaults.set(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-20 * day)),
                     forKey: "trialStartedAt")
        let s = service()
        XCTAssertEqual(s.state, .trialExpired)
        XCTAssertFalse(s.canDictate)
    }
    func testActivateValidKeyLicenses() {
        let s = service()
        let result = s.activate(LicenseFixtures.validToken)
        XCTAssertNoThrow(try result.get())
        guard case .licensed(let lic) = s.state else { return XCTFail("expected licensed") }
        XCTAssertEqual(lic.name, LicenseFixtures.validName)
        XCTAssertTrue(s.canDictate)
        // persisted: a fresh service loads as licensed
        XCTAssertEqual(service().state, .licensed(lic))
    }
    func testActivateBadKeyKeepsState() {
        let s = service()
        let before = s.state
        // Result<Void, LicenseError> isn't Equatable (Void isn't), so match the case.
        guard case .failure(let error) = s.activate("garbage") else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(error, .malformed)
        XCTAssertEqual(s.state, before)
    }
    func testRemoveLicenseReturnsToTrial() {
        let s = service()
        _ = s.activate(LicenseFixtures.validToken)
        s.removeLicense()
        guard case .trial = s.state else { return XCTFail("expected trial after removal") }
    }
    func testLicensedSurvivesExpiredTrial() {
        defaults.set(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-20 * day)),
                     forKey: "trialStartedAt")
        let s = service()
        XCTAssertEqual(s.state, .trialExpired)
        _ = s.activate(LicenseFixtures.validToken)
        XCTAssertTrue(s.canDictate)                 // license overrides expired trial
    }
    func testRefreshCatchesMidSessionExpiry() {
        // Long-running menu-bar app: trial expires while it stays open. A mutable
        // `now` (captured in the injected closure) lets the test advance the clock.
        var currentNow = Date()
        let s = LicenseService(verifier: verifier(),
                               clock: TrialClock(defaults: defaults, fileURL: trialFile, trialDays: 14),
                               defaults: defaults, now: { currentNow })
        guard case .trial(let d) = s.state else { return XCTFail("expected trial") }
        XCTAssertEqual(d, 14)
        XCTAssertTrue(s.canDictate)
        currentNow = currentNow.addingTimeInterval(20 * day)   // trial elapses in-session
        s.refresh()
        XCTAssertEqual(s.state, .trialExpired)
        XCTAssertFalse(s.canDictate)
    }
    func testCorruptStoredTokenDegradesToTrial() {
        defaults.set("garbage", forKey: "licenseKey")
        let s = service()
        XCTAssertEqual(s.state, .trial(daysLeft: 14))   // not a crash, not licensed
    }
    func testRemoveLicenseWhenTrialExpiredReturnsExpired() {
        defaults.set(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-20 * day)),
                     forKey: "trialStartedAt")
        let s = service()
        _ = s.activate(LicenseFixtures.validToken)
        s.removeLicense()
        XCTAssertEqual(s.state, .trialExpired)          // re-derive, not a hard-set to trial
    }
}
