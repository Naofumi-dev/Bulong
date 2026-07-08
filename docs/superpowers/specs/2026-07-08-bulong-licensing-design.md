# Bulong Licensing + Trial — Design

Date: 2026-07-08
Status: approved by Armageddon (offline signed keys, 14-day full trial, firm-but-fair enforcement)
Phase 3 sub-project 2 of 4. Siblings, not covered here: notarized distribution, landing page (done), pricing finalization, and the purchase-webhook → key-signer (deferred until the Lemon Squeezy account exists).

## Context and decisions (locked)

- **Offline, cryptographically-signed license keys.** Ed25519. The app bundles the **public** verifying key and validates a license **entirely locally — zero network calls, ever.** This is the only licensing approach consistent with "your Mac never phones home." Lemon Squeezy's built-in license API validates online and is therefore NOT used for validation; LS is used later only to trigger our own signer.
- **Trial:** 14-day, full-featured. Everything works for 14 days, then the app requires a license to dictate.
- **Enforcement — firm but fair:** after the trial, dictation is blocked with a clear buy/enter-key path, but Settings and History stay fully accessible. Never brick the app; never hold data hostage.
- **Anti-piracy is humane.** Trial-start is stored locally in two places and the earliest wins; a determined user who wipes both to reset the trial is tolerated. No invasive DRM — it would contradict the trust brand and waste effort.
- **Buildable now:** the entire app side (verifier, trial clock, service, gate, Settings UI, expired flow) against a local dev key pair + a dev signing script, fully TDD'd. **Deferred:** production key-pair generation, the LS webhook → signer, the real Buy URL (placeholder → the site for now).

## Architecture

New files under `LocalTalk/Services/Licensing/` plus small integration points. All `@MainActor` where they touch app state; the verifier is pure and isolate-testable.

### 1. `LicenseVerifier` (pure, no I/O)
- CryptoKit `Curve25519.Signing.PublicKey(rawRepresentation:)` + `isValidSignature(_:for:)`.
- Bundled public key: a 32-byte Ed25519 raw key, stored base64 in a constant (dev key now; swapped for the production key at launch — one-line change, documented).
- API: `func verify(_ key: String) -> Result<License, LicenseError>` — parses the two-part token, base64url-decodes payload+signature, verifies the signature over the exact payload bytes, decodes the payload JSON to a `License`. No trust in the payload until the signature checks out.

### 2. Types — `License.swift`
```swift
struct License: Codable, Equatable {
    var name: String
    var email: String
    var order: String
    var issued: Date          // ISO-8601 in the signed payload
}
enum LicenseError: Error, Equatable {
    case malformed            // not a two-part base64url token
    case badSignature         // signature does not verify against the bundled key
    case unreadablePayload    // signature ok but JSON won't decode
}
enum LicenseState: Equatable {
    case trial(daysLeft: Int)
    case trialExpired
    case licensed(License)
}
```
- Key token format: `<base64url(payloadJSON)>.<base64url(signature)>`. Single line. Payload JSON keys exactly `name,email,order,issued`.

### 3. `TrialClock`
- Trial start persisted in **two** stores: `UserDefaults` key `trialStartedAt` (ISO-8601 string) and a file `~/Library/Application Support/Bulong/trial` (same string). On first read, if either is missing it's written from the other or from "now"; the **effective start is the earliest** of the present values, so deleting one store cannot extend the trial.
- `daysLeft(now:) -> Int` = `max(0, 14 - floor((now - start) / 86400))`, injectable `now` for tests.
- Clock-rollback note: also stores `lastSeen`; if `now < start`, treat start as unchanged (never credit negative time). Full rollback-proofing is out of scope (humane posture); documented.
- Injectable `defaults:` and `fileURL:` for tests (mirrors `SettingsStore`/`HistoryStore` patterns already in the app).

### 4. `LicenseService` (@MainActor @Observable)
- Depends on `LicenseVerifier`, `TrialClock`, a `UserDefaults` (stores the activated license token under `licenseKey`).
- On init: if a stored token verifies → `.licensed`; else derive from the trial clock → `.trial(daysLeft>0)` or `.trialExpired`.
- Published: `state: LicenseState`, plus computed `canDictate: Bool` (true for `.licensed` and `.trial`, false for `.trialExpired`), `daysLeft: Int?`, `licenseeName: String?`.
- `activate(_ key: String) -> Result<Void, LicenseError>` — verifies; on success stores the token and sets `.licensed`; on failure returns the error and leaves state unchanged.
- `removeLicense()` — clears the stored token and re-derives trial state.

### 5. Integration — dictation gate
- `AppModel` gains an injected `canDictate: @MainActor () -> Bool` (default `{ true }` so existing tests/compose stay green). `startDictation()` checks it first; if false it does not record — it sets a state/flag that routes to the expired prompt (a new `DictationState` is NOT added; instead `startDictation` early-returns and calls an injected `onDictationBlocked: () -> Void`).
- `AppComposition` wires `canDictate: { licenseService.canDictate }` and `onDictationBlocked` to open the main window at Settings → License (reusing `AppComposition.uiState.mainSection = .settings` + `openWindow`/activate). No recording HUD is shown when blocked (nothing is recording). Instead the **menu-bar popover** reflects the expired state in its status line ("Trial ended — buy to continue"), so the feedback is where the user's attention already is when they press the hotkey.

### 6. UI — Settings "License" section (new SectionCard)
- Placed first or last in `SettingsView`. Shows, by state:
  - `.trial(n)` → "Trial · {n} days left" (mono) + a quiet "Buy Bulong" `BorderedActionButtonStyle` (emphasized).
  - `.trialExpired` → "Your 14-day trial has ended" (in `Theme.failure`) + prominent Buy + the key field.
  - `.licensed(l)` → "Licensed to {l.name}" + a mono order ref + a quiet "Remove license".
- A license-key field (paste + Activate) available in trial/expired states; on Activate, show inline success ("Thanks — you're licensed.") or the specific error ("That key looks malformed." / "That key didn't verify." / "That key isn't for Bulong.").
- Buy button opens the site pricing (placeholder `https://bulong.app/#pricing`) via `NSWorkspace`; documented as wired to the real checkout later.

### 7. Dev tooling — `script/sign_license.swift`
- Standalone Swift (CryptoKit), run with `swift script/sign_license.swift`. Two modes: `--genkey` prints a fresh base64 Ed25519 private+public pair (for generating the dev and, later, production keys), and the default mode signs a license from `--name --email --order` using a private key (env/arg), printing the key token. The app bundles the matching public key. The private key is NEVER committed; the dev key pair used for tests is a fixed test vector committed only as its public half + test tokens in the test target.

## States, data flow, errors

- Fresh install → TrialClock writes `now` to both stores → `.trial(14)`.
- Each launch/day → `LicenseService` recomputes; trial counts down; at 0 with no license → `.trialExpired` → `canDictate=false`.
- User buys → receives a key token by email → pastes into Settings → `activate` verifies offline → `.licensed` forever (no expiry on the license itself for v1; "lifetime updates through 1.x" per the site).
- All verification is offline; the only error class is malformed/bad-signature/unreadable — surfaced as clear inline copy. No crashes, no network states.

## Privacy

The license token, the licensee's name/email, and the trial timestamps never leave the Mac. No activation server, no phone-home, no analytics. This is verifiable (no network entitlement is used on the licensing path) and becomes a marketing line: "even the license check is offline."

## Testing (TDD)

- **LicenseVerifier** (pure, fast): a committed test key pair (public + a set of signed tokens). Valid token → `.success(License)` with correct fields; tampered payload byte → `.badSignature`; token signed by a different key → `.badSignature`; non-two-part / bad base64 → `.malformed`; valid signature over non-JSON payload → `.unreadablePayload`.
- **TrialClock**: fresh → 14; injected `now` +5 days → 9; +14 → 0 (expired); +20 → 0 (clamped); deleting the UserDefaults store but keeping the older file → start unchanged (earliest wins); `now` < start → no negative credit.
- **LicenseService** state machine: no token + fresh clock → `.trial`; store a valid token → `.licensed`; expired clock + no token → `.trialExpired`; `activate` with a good key flips to `.licensed` and persists; `activate` with each bad key returns the right error and leaves state; `removeLicense` returns to the trial/expired derivation; `canDictate` matches state.
- **AppModel gate**: with `canDictate = { false }`, `startDictation` records nothing and invokes `onDictationBlocked` (verified via a recording closure + FakeEngine); with `{ true }`, existing flow unchanged (regression-guards the default).
- Full existing suite stays green under the new injected params (all defaulted).

## Out of scope (deferred / other sub-projects)

- **Production key pair** — generated once at launch (via `--genkey`); the private key stored offline/secret; the public half replaces the bundled dev key (documented one-line swap).
- **Purchase → key issuance** — a small function that, on a Lemon Squeezy `order_created` webhook, signs a license with the production private key and emails the buyer their token. Needs the LS account; separate sub-project.
- **Real Buy URL / checkout** — wired when LS is live; placeholder points at the site.
- **Device-count enforcement, license expiry, upgrade pricing for 2.0** — not in v1; the payload has room to add fields later without breaking older licenses (verifier ignores unknown keys).
- No changes to the transcription, HUD, history, or onboarding beyond the single dictation-gate hook and the Settings section.
