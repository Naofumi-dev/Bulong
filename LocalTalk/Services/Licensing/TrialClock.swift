import Foundation

/// Trial-start persistence across two local stores; the EARLIEST present value
/// wins so deleting one store can't extend the trial. Humane, not invasive.
struct TrialClock {
    private let defaults: UserDefaults
    private let fileURL: URL
    private let trialDays: Int
    private let iso = ISO8601DateFormatter()
    private static let key = "trialStartedAt"

    init(defaults: UserDefaults = .standard,
         fileURL: URL = TrialClock.defaultFileURL,
         trialDays: Int = 14) {
        self.defaults = defaults
        self.fileURL = fileURL
        self.trialDays = trialDays
    }

    static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bulong", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("trial")
    }

    /// Days remaining in the trial (0...trialDays). Establishes and persists the
    /// start on first call. `now` is injectable for tests.
    func daysLeft(now: Date = Date()) -> Int {
        let start = effectiveStart(now: now)
        let used = now.timeIntervalSince(start)
        let left = Double(trialDays) - floor(used / 86_400)
        return Int(max(0, min(Double(trialDays), left)))
    }

    private func effectiveStart(now: Date) -> Date {
        var candidates: [Date] = []
        if let s = defaults.string(forKey: Self.key), let d = iso.date(from: s) { candidates.append(d) }
        if let s = try? String(contentsOf: fileURL, encoding: .utf8), let d = iso.date(from: s) {
            candidates.append(d)
        }
        let start = candidates.min() ?? now
        // Persist the resolved start back to BOTH stores (idempotent; heals a missing one).
        let str = iso.string(from: start)
        if defaults.string(forKey: Self.key) != str { defaults.set(str, forKey: Self.key) }
        if (try? String(contentsOf: fileURL, encoding: .utf8)) != str {
            try? str.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return start
    }
}
