# Bulong Licensing + Trial Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add offline Ed25519 license validation + a 14-day trial with firm-but-fair enforcement to the Bulong app, per `docs/superpowers/specs/2026-07-08-bulong-licensing-design.md`.

**Architecture:** New `LocalTalk/Services/Licensing/` module — a pure `LicenseVerifier` (CryptoKit, injectable public key), a two-store `TrialClock`, and a `@MainActor @Observable LicenseService` state machine. `AppModel` gains an injected dictation gate. Settings gets a License section. Zero network on the licensing path.

**Tech Stack:** Swift 6, CryptoKit (`Curve25519.Signing`), Foundation, SwiftUI, XCTest. A standalone `script/sign_license.swift` mints keys/licenses for dev + tests.

**Ground rules (every task):**
- BUILD/TEST: `xcodegen generate && xcodebuild test -project Bulong.xcodeproj -scheme Bulong -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5` (run `xcodegen generate` after any file add). Timeout up to 600000 ms.
- Hard rules from the app carry over: no `Color(red:` outside Theme.swift, no `.green`, no ad-hoc font sizes in new SwiftUI (use `Theme.Fonts.*`), press feedback via the existing styles, Reduce Motion respected.
- Commit hygiene: explicit `git add <paths>` only — the repo root has untracked `weave_test_recording_*.mp3` that must never be committed. End commit messages with the `Co-Authored-By: Claude Fable 5` trailer.
- All licensing verification is OFFLINE — no URLSession, no network entitlement on this path.

---

## File structure

```
LocalTalk/Services/Licensing/
  License.swift            types: License, LicenseError, LicenseState
  LicenseVerifier.swift    pure Ed25519 verify (injectable public key) + bundled key constant
  TrialClock.swift         two-store trial-start persistence + daysLeft
  LicenseService.swift     @MainActor @Observable state machine (verify, trial, activate, remove)
LocalTalk/AppModel.swift             MODIFIED: canDictate/onDictationBlocked gate
LocalTalk/LocalTalkApp.swift         MODIFIED: AppComposition wires licenseService + gate
LocalTalk/UI/MainWindow/SettingsView.swift   MODIFIED: License SectionCard
LocalTalk/UI/MenuPopoverView.swift   MODIFIED: expired status line
LocalTalkTests/
  LicenseFixtures.swift    committed TEST keypair (both halves) + signed test tokens
  LicenseVerifierTests.swift
  TrialClockTests.swift
  LicenseServiceTests.swift
  AppModelTests.swift      MODIFIED: gate tests
script/sign_license.swift  --genkey | sign a license (dev + fixtures)
```

---

### Task 1: Signing tool + committed test key pair + fixtures

**Files:** Create `script/sign_license.swift`, `LocalTalkTests/LicenseFixtures.swift`

- [ ] **Step 1: Write `script/sign_license.swift`** (standalone, run via `swift`):

```swift
import Foundation
import CryptoKit

// Usage:
//   swift script/sign_license.swift --genkey
//   swift script/sign_license.swift --priv <base64-privkey> --name "Jo" --email "jo@x.com" --order "TEST-1"
func arg(_ n: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: n), i + 1 < a.count else { return nil }
    return a[i + 1]
}
func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

if CommandLine.arguments.contains("--genkey") {
    let key = Curve25519.Signing.PrivateKey()
    print("PRIVATE(base64): \(key.rawRepresentation.base64EncodedString())")
    print("PUBLIC(base64):  \(key.publicKey.rawRepresentation.base64EncodedString())")
    exit(0)
}

guard let privB64 = arg("--priv"),
      let priv = Data(base64Encoded: privB64),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: priv),
      let name = arg("--name"), let email = arg("--email"), let order = arg("--order") else {
    FileHandle.standardError.write(Data("need --priv --name --email --order (or --genkey)\n".utf8)); exit(1)
}
let iso = ISO8601DateFormatter()
let payload: [String: String] = ["name": name, "email": email, "order": order, "issued": iso.string(from: Date())]
let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
let sig = try key.signature(for: payloadData)
print("\(b64url(payloadData)).\(b64url(sig))")
```

- [ ] **Step 2: Generate a fixed TEST key pair and tokens**

```bash
cd /Users/armageddonvivas/Documents/Codex/2026-07-05/hey-codex-i-want-to-create/outputs/LocalTalk
swift script/sign_license.swift --genkey        # capture PRIVATE + PUBLIC
# with the printed private key:
swift script/sign_license.swift --priv <PRIV> --name "Test User" --email "test@bulong.app" --order "TEST-0001"
```
Record the PUBLIC base64, the PRIVATE base64 (test only), and one signed token.

- [ ] **Step 3: Write `LocalTalkTests/LicenseFixtures.swift`** with the generated values (paste the real base64 from Step 2 — these are TEST vectors, safe to commit):

```swift
import Foundation
@testable import Bulong

// TEST key pair + vectors ONLY. The production key is generated at launch and never committed.
enum LicenseFixtures {
    static let testPublicKeyB64 = "PASTE_PUBLIC_BASE64"
    static let testPrivateKeyB64 = "PASTE_PRIVATE_BASE64"   // used to mint tokens in-test
    static let validToken = "PASTE_SIGNED_TOKEN"            // for Test User / test@bulong.app / TEST-0001
    static let validName = "Test User"
}
```

- [ ] **Step 4: Verify the token round-trips with a throwaway check + commit**

```bash
swift -e 'import CryptoKit,Foundation; /* eyeball: token has exactly one "." and two base64url halves */' 2>/dev/null || true
git add script/sign_license.swift LocalTalkTests/LicenseFixtures.swift
git commit -m "feat(license): signing tool and committed test key fixtures"
```

---

### Task 2: License types + LicenseVerifier (TDD)

**Files:** Create `LocalTalk/Services/Licensing/License.swift`, `LocalTalk/Services/Licensing/LicenseVerifier.swift`; Test `LocalTalkTests/LicenseVerifierTests.swift`

- [ ] **Step 1: Write `LocalTalk/Services/Licensing/License.swift`**

```swift
import Foundation

struct License: Codable, Equatable {
    var name: String
    var email: String
    var order: String
    var issued: Date
}

enum LicenseError: Error, Equatable {
    case malformed          // not a two-part base64url token
    case badSignature       // signature does not verify against the key
    case unreadablePayload  // signature ok but JSON won't decode
}

enum LicenseState: Equatable {
    case trial(daysLeft: Int)
    case trialExpired
    case licensed(License)
}
```

- [ ] **Step 2: Write failing tests `LocalTalkTests/LicenseVerifierTests.swift`**

```swift
import XCTest
import CryptoKit
@testable import Bulong

final class LicenseVerifierTests: XCTestCase {
    private func verifier() -> LicenseVerifier {
        let pub = try! Curve25519.Signing.PublicKey(
            rawRepresentation: Data(base64Encoded: LicenseFixtures.testPublicKeyB64)!)
        return LicenseVerifier(publicKey: pub)
    }

    func testValidTokenVerifies() {
        let result = verifier().verify(LicenseFixtures.validToken)
        guard case .success(let lic) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(lic.name, LicenseFixtures.validName)
        XCTAssertEqual(lic.order, "TEST-0001")
    }

    func testMalformedTokenRejected() {
        XCTAssertEqual(verifier().verify("not-a-token"), .failure(.malformed))
        XCTAssertEqual(verifier().verify("only.one.dot.too.many"), .failure(.malformed))
        XCTAssertEqual(verifier().verify(""), .failure(.malformed))
    }

    func testTamperedPayloadRejected() {
        // Flip a character in the payload half — signature must fail.
        var parts = LicenseFixtures.validToken.split(separator: ".").map(String.init)
        let first = parts[0]
        let flipped = String(first.dropLast()) + (first.hasSuffix("A") ? "B" : "A")
        parts[0] = flipped
        XCTAssertEqual(verifier().verify(parts.joined(separator: ".")), .failure(.badSignature))
    }

    func testWrongKeyRejected() {
        // A token signed by a different private key must not verify against our public key.
        let otherPriv = Curve25519.Signing.PrivateKey()
        let payload = try! JSONSerialization.data(
            withJSONObject: ["name":"X","email":"x@x","order":"O","issued":"2026-01-01T00:00:00Z"],
            options: [.sortedKeys])
        let sig = try! otherPriv.signature(for: payload)
        func b64url(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of:"+",with:"-")
                .replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        }
        XCTAssertEqual(verifier().verify("\(b64url(payload)).\(b64url(sig))"), .failure(.badSignature))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run BUILD/TEST → compile failure: `LicenseVerifier` not found.

- [ ] **Step 4: Write `LocalTalk/Services/Licensing/LicenseVerifier.swift`**

```swift
import Foundation
import CryptoKit

struct LicenseVerifier {
    private let publicKey: Curve25519.Signing.PublicKey

    init(publicKey: Curve25519.Signing.PublicKey) {
        self.publicKey = publicKey
    }

    /// The bundled PRODUCTION public key. REPLACE the base64 below with the
    /// production key before shipping (the matching private key is generated
    /// once via `sign_license.swift --genkey` and kept offline, never committed).
    /// Until then this equals the committed test key — a launch blocker if unswapped.
    static let bundledPublicKeyB64 = "PASTE_SAME_AS_TEST_PUBLIC_FOR_NOW"

    static func bundled() -> LicenseVerifier {
        let data = Data(base64Encoded: bundledPublicKeyB64)!
        let key = try! Curve25519.Signing.PublicKey(rawRepresentation: data)
        return LicenseVerifier(publicKey: key)
    }

    func verify(_ token: String) -> Result<License, LicenseError> {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payload = Self.b64urlDecode(String(parts[0])),
              let sig = Self.b64urlDecode(String(parts[1])),
              !payload.isEmpty, !sig.isEmpty else {
            return .failure(.malformed)
        }
        guard publicKey.isValidSignature(sig, for: payload) else {
            return .failure(.badSignature)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let license = try? decoder.decode(License.self, from: payload) else {
            return .failure(.unreadablePayload)
        }
        return .success(license)
    }

    private static func b64urlDecode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }
}
```

Set `bundledPublicKeyB64` to the SAME base64 as `LicenseFixtures.testPublicKeyB64` for now (so an activation works in dev with a token from `sign_license.swift`). Note the swap-before-launch requirement in the constant's doc comment (already there).

- [ ] **Step 5: Run tests to verify they pass**

Run BUILD/TEST → all `LicenseVerifierTests` pass. NOTE: the `License.issued` decoder uses `.iso8601`; the signing script emits ISO-8601 — confirm the fixture token decodes (if the payload date format and decoder disagree, fix the script to emit `iso.string(from:)` which is ISO-8601 by default — they match).

- [ ] **Step 6: Commit**

```bash
git add LocalTalk/Services/Licensing/License.swift LocalTalk/Services/Licensing/LicenseVerifier.swift LocalTalkTests/LicenseVerifierTests.swift
git commit -m "feat(license): offline Ed25519 license verifier"
```

---

### Task 3: TrialClock (TDD)

**Files:** Create `LocalTalk/Services/Licensing/TrialClock.swift`; Test `LocalTalkTests/TrialClockTests.swift`

- [ ] **Step 1: Write failing tests `LocalTalkTests/TrialClockTests.swift`**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail** (TrialClock not found).

- [ ] **Step 3: Write `LocalTalk/Services/Licensing/TrialClock.swift`**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass.** (Regenerate + test; 4 TrialClock tests green.)

- [ ] **Step 5: Commit**

```bash
git add LocalTalk/Services/Licensing/TrialClock.swift LocalTalkTests/TrialClockTests.swift
git commit -m "feat(license): two-store trial clock with earliest-wins start"
```

---

### Task 4: LicenseService state machine (TDD)

**Files:** Create `LocalTalk/Services/Licensing/LicenseService.swift`; Test `LocalTalkTests/LicenseServiceTests.swift`

- [ ] **Step 1: Write failing tests `LocalTalkTests/LicenseServiceTests.swift`**

```swift
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
        XCTAssertEqual(s.activate("garbage"), .failure(.malformed))
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
}
```

- [ ] **Step 2: Run tests to verify they fail** (LicenseService not found).

- [ ] **Step 3: Write `LocalTalk/Services/Licensing/LicenseService.swift`**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass** (6 LicenseService tests green).

- [ ] **Step 5: Commit**

```bash
git add LocalTalk/Services/Licensing/LicenseService.swift LocalTalkTests/LicenseServiceTests.swift
git commit -m "feat(license): LicenseService state machine (trial, activate, remove)"
```

---

### Task 5: AppModel dictation gate (TDD)

**Files:** Modify `LocalTalk/AppModel.swift`; Modify `LocalTalkTests/AppModelTests.swift`

- [ ] **Step 1: Add failing tests to `LocalTalkTests/AppModelTests.swift`**

Add to the existing `AppModelTests` (mirror the file's existing `makeModel` helper; it constructs `AppModel` with defaulted closures). Extend `makeModel` to accept an optional gate, or add a dedicated builder:

```swift
    @MainActor func testBlockedWhenCannotDictate() async {
        var blockedCalls = 0
        let engine = FakeEngine()
        let audio = AudioStub()
        let model = AppModel(
            settings: SettingsStore(defaults: defaults),
            history: HistoryStore(fileURL: tmpHistory),
            engineProvider: { _ in engine },
            audioStart: { audio.start() },
            audioStop: { audio.stop() },
            insertText: { _ in .insertedDirectly },
            frontmostAppName: { "TextEdit" },
            canDictate: { false },
            onDictationBlocked: { blockedCalls += 1 }
        )
        await model.toggleDictation()
        XCTAssertEqual(model.state, .idle)          // never entered recording
        XCTAssertEqual(blockedCalls, 1)
        XCTAssertEqual(audio.startCount, 0)         // no audio captured
    }

    @MainActor func testAllowedWhenCanDictate() async {
        let engine = FakeEngine()
        let audio = AudioStub()
        let model = AppModel(
            settings: SettingsStore(defaults: defaults),
            history: HistoryStore(fileURL: tmpHistory),
            engineProvider: { _ in engine },
            audioStart: { audio.start() },
            audioStop: { audio.stop() },
            insertText: { _ in .insertedDirectly },
            frontmostAppName: { "TextEdit" },
            canDictate: { true }
        )
        await model.toggleDictation()
        guard case .recording = model.state else { return XCTFail("expected recording") }
        await model.cancelDictation()
    }
```

(If `AudioStub` lacks `startCount`, add a simple counter to it in the test file. If existing tests call `AppModel(...)` positionally, the new params are appended with defaults so they keep compiling.)

- [ ] **Step 2: Run tests to verify they fail** (unknown params `canDictate`/`onDictationBlocked`).

- [ ] **Step 3: Modify `LocalTalk/AppModel.swift`**

Add stored props (near line 26-29):
```swift
    private let canDictate: @MainActor () -> Bool
    private let onDictationBlocked: @MainActor () -> Void
```
Add to `init` params (appended, defaulted — keeps every existing call site compiling):
```swift
        canDictate: @escaping @MainActor () -> Bool = { true },
        onDictationBlocked: @escaping @MainActor () -> Void = {},
```
Assign in the init body:
```swift
        self.canDictate = canDictate
        self.onDictationBlocked = onDictationBlocked
```
Gate at the very top of `startDictation()` (before `captureTarget()`):
```swift
        guard canDictate() else {
            onDictationBlocked()
            return
        }
```

- [ ] **Step 4: Run the FULL suite to verify pass** (new gate tests green; all prior AppModel/other tests still green because the params are defaulted).

- [ ] **Step 5: Commit**

```bash
git add LocalTalk/AppModel.swift LocalTalkTests/AppModelTests.swift
git commit -m "feat(license): gate dictation start on canDictate"
```

---

### Task 6: Settings License section + composition wiring + popover status

**Files:** Modify `LocalTalk/LocalTalkApp.swift`, `LocalTalk/UI/MainWindow/SettingsView.swift`, `LocalTalk/UI/MenuPopoverView.swift`

- [ ] **Step 1: Wire `LicenseService` into `AppComposition`** (LocalTalkApp.swift)

Add `static let license = LicenseService()`. In `makeAppModel`, pass:
```swift
            canDictate: { license.canDictate },
            onDictationBlocked: {
                uiState.mainSection = .settings
                openMainWindow()          // small helper: openWindow(id:"main") + NSApp.activate()
            },
```
Add a `@MainActor static func openMainWindow()` if one isn't already factored — reuse the popover's existing open logic (an `EnvironmentValues().openWindow`-free path: post to the `Window` scene via `NSApp` + the existing `uiState`). If `openWindow` isn't reachable from composition, set `uiState.mainSection = .settings` and rely on the popover's "Trial ended" line (Step 3) to prompt the user to open the window — do NOT invent fragile window plumbing; report which path was used.

- [ ] **Step 2: Add the License `SectionCard` to `SettingsView`**

Add `var license: LicenseService` to `SettingsView` (passed from `MainWindowView` → from `AppComposition.license`; thread it through like `modelManager`). Add a section (place it LAST, after Permissions):

```swift
                SectionCard(title: "License") {
                    switch license.state {
                    case .licensed(let l):
                        row("Licensed") {
                            Text(l.name).font(Theme.Fonts.mono(12)).foregroundStyle(Theme.textSecondary)
                        }
                        divider
                        row("") {
                            Button("Remove license") { license.removeLicense() }
                                .buttonStyle(HoverButtonStyle())
                        }
                    case .trial(let d):
                        row("Trial") {
                            Text("\(d) days left").font(Theme.Fonts.mono(12)).foregroundStyle(Theme.textSecondary)
                        }
                        divider
                        buyRow
                        divider
                        activateRow
                    case .trialExpired:
                        row("Trial ended") {
                            Text("Buy to keep dictating").font(Theme.Fonts.caption).foregroundStyle(Theme.failure)
                        }
                        divider
                        buyRow
                        divider
                        activateRow
                    }
                }
```

Add these helpers to `SettingsView` (state for the key field + result message):
```swift
    @State private var licenseKeyField = ""
    @State private var licenseMessage: String?

    private var buyRow: some View {
        row("Buy Bulong") {
            Button("Buy — $29") {
                if let url = URL(string: "https://bulong.app/#pricing") { NSWorkspace.shared.open(url) }
            }.buttonStyle(BorderedActionButtonStyle(emphasized: true))
        }
    }
    private var activateRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Paste your license key", text: $licenseKeyField)
                    .textFieldStyle(.plain).font(Theme.Fonts.mono(11))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.ink1))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).stroke(Theme.hairline, lineWidth: 1))
                Button("Activate") {
                    switch license.activate(licenseKeyField.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    case .success: licenseMessage = "Thanks — you're licensed."; licenseKeyField = ""
                    case .failure(let e): licenseMessage = Self.message(for: e)
                    }
                }.buttonStyle(BorderedActionButtonStyle())
            }
            if let m = licenseMessage {
                Text(m).font(Theme.Fonts.caption)
                    .foregroundStyle(license.licenseeName != nil ? Theme.accent : Theme.failure)
            }
        }
    }
    private static func message(for e: LicenseError) -> String {
        switch e {
        case .malformed: return "That key looks malformed. Copy the whole key from your email."
        case .badSignature: return "That key didn't verify — check for a copy/paste slip."
        case .unreadablePayload: return "That key isn't for Bulong."
        }
    }
```

(If `row(_:control:)` signature differs, match the file's existing helper. `divider` is the file's existing hairline; reuse it.)

- [ ] **Step 3: Popover "Trial ended" status** (MenuPopoverView.swift)

Thread `license` into `MenuPopoverView` (from `AppComposition.license`). In `stateText`, when `model.state == .idle` and `!license.canDictate`, return "Trial ended — buy to continue" (in `Theme.failure` via the existing `isFailed`-style branch — add a small `trialEnded` bool). Keep it a status line only; the Buy action lives in Settings.

- [ ] **Step 4: Build, tests, manual verify**

BUILD/TEST green. Manual (user or dev):
1. Fresh: Settings → License shows "Trial · 14 days left" + Buy + key field.
2. Mint a dev key: `swift script/sign_license.swift --priv <dev-priv> --name "You" --email you@x --order DEV-1`; paste into the field → "Thanks — you're licensed."; section shows "Licensed / You"; Remove returns to trial.
3. Force expiry: `defaults write com.armageddonvivas.Bulong trialStartedAt "2026-06-01T00:00:00Z"`, relaunch → License shows "Trial ended"; pressing the hotkey opens Settings→License and does NOT record; popover says "Trial ended — buy to continue". Reset: `defaults delete com.armageddonvivas.Bulong trialStartedAt` and delete `~/Library/Application Support/Bulong/trial`.

- [ ] **Step 5: Commit**

```bash
git add LocalTalk/LocalTalkApp.swift LocalTalk/UI/MainWindow/SettingsView.swift LocalTalk/UI/MenuPopoverView.swift
git commit -m "feat(license): Settings license section, dictation-blocked prompt, popover status"
```

---

## Self-review notes (for the executor)

- **Spec coverage:** verifier (T2), trial clock (T3), service+activate/remove (T4), dictation gate (T5), Settings UI + popover + buy placeholder (T6), signing tool + fixtures (T1). Every spec section maps to a task.
- **The bundled key** equals the committed TEST public key during this phase (so dev activation works) — the doc comment marks swapping to the production key as a launch blocker. Do NOT ship without swapping.
- **Offline guarantee:** nothing in `Services/Licensing/` imports URLSession or touches the network; the only "Buy" action opens a URL in the browser (user-initiated), which is not a phone-home.
- **Backwards-compatible init:** AppModel's new params are appended + defaulted so every existing test/compose call compiles unchanged; run the FULL suite after T5.
- **Date format:** the signing script and the `.iso8601` decoder must agree; T2 Step 5 calls this out — verify the fixture token actually decodes before moving on.
- **Window-open from composition (T6 Step 1):** if reliable `openWindow` plumbing from `AppComposition` proves fragile, fall back to the popover status prompt and report the chosen path — do not invent brittle AppKit window code.
- Never `git add -A` (repo-root mp3s). No changes to transcription/HUD/history/onboarding beyond the gate hook and the two UI touch-points.

