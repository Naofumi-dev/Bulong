import Foundation
import Observation

@MainActor @Observable
final class LicenseService {
    private(set) var state: LicenseState

    private let verifier: LicenseVerifier
    private let clock: TrialClock
    private let defaults: UserDefaults
    private let now: () -> Date
    private static let tokenKey = "licenseKey"

    init(verifier: LicenseVerifier = .bundled(),
         clock: TrialClock = TrialClock(),
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init) {
        self.verifier = verifier
        self.clock = clock
        self.defaults = defaults
        self.now = now
        self.state = Self.derive(verifier: verifier, clock: clock, defaults: defaults, now: now)
    }

    var canDictate: Bool {
        switch state { case .licensed, .trial: return true; case .trialExpired: return false }
    }
    var daysLeft: Int? { if case .trial(let d) = state { return d } else { return nil } }
    var licenseeName: String? { if case .licensed(let l) = state { return l.name } else { return nil } }

    @discardableResult
    func activate(_ token: String) -> Result<Void, LicenseError> {
        switch verifier.verify(token) {
        case .success(let license):
            defaults.set(token, forKey: Self.tokenKey)
            state = .licensed(license)
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    func removeLicense() {
        defaults.removeObject(forKey: Self.tokenKey)
        state = Self.derive(verifier: verifier, clock: clock, defaults: defaults, now: now)
    }

    /// Re-derive state so a trial that expires while the (long-running menu-bar)
    /// app stays open re-gates without a relaunch. Licensed stays licensed.
    func refresh() {
        state = Self.derive(verifier: verifier, clock: clock, defaults: defaults, now: now)
    }

    private static func derive(verifier: LicenseVerifier, clock: TrialClock,
                               defaults: UserDefaults, now: () -> Date) -> LicenseState {
        if let token = defaults.string(forKey: tokenKey),
           case .success(let license) = verifier.verify(token) {
            return .licensed(license)
        }
        let left = clock.daysLeft(now: now())
        return left > 0 ? .trial(daysLeft: left) : .trialExpired
    }
}
