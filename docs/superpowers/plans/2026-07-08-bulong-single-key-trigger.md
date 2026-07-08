# Bulong Single-Key Trigger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Right-Option hold-or-tap single-key dictation trigger alongside the combo hotkey, per `docs/superpowers/specs/2026-07-08-bulong-single-key-trigger-design.md`.

**Architecture:** A pure, TDD'd `SingleKeyTrigger` hold/tap state machine; an `NSEvent` `.flagsChanged` monitor in `HotkeyService` that detects Right Option (device-dependent right-alternate bit) on the main thread and feeds the state machine; a `TriggerKind` setting + Settings UI; composition wiring that swaps the combo ↔ single-key and resets on idle.

**Tech Stack:** Swift 6, AppKit `NSEvent` monitors (main-thread delivery — deliberately NOT a CGEventTap), SwiftUI, XCTest.

**Ground rules (every task):**
- BUILD/TEST: `xcodegen generate && xcodebuild test -project Bulong.xcodeproj -scheme Bulong -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5` (regenerate after file add; timeout up to 600000).
- Token/brand rules for any SwiftUI (no Color(red: outside Theme, no .green, no ad-hoc font sizes; reuse existing styles).
- Commit hygiene: explicit `git add <paths>` — NEVER `git add -A` (repo root has untracked `weave_test_recording_*.mp3`). Trailer `Co-Authored-By: Claude Fable 5`.
- Threading: the monitor handler runs on the main thread (NSEvent monitors deliver on main) — so `@MainActor` access is safe. Do NOT introduce a CGEventTap (that runs off-main and is the crash class we just fixed in AudioService).

---

## File structure

```
LocalTalk/Core/Types.swift            MODIFIED: TriggerKind enum
LocalTalk/Services/SingleKeyTrigger.swift   NEW: pure hold/tap state machine
LocalTalk/Services/SettingsStore.swift      MODIFIED: triggerKind persisted property
LocalTalk/Services/HotkeyService.swift      MODIFIED: NSEvent right-option monitor
LocalTalk/LocalTalkApp.swift          MODIFIED: AppComposition wiring (combo↔single-key, reset on idle)
LocalTalk/UI/MainWindow/SettingsView.swift  MODIFIED: Trigger choice in the Hotkey section
LocalTalkTests/SingleKeyTriggerTests.swift  NEW
LocalTalkTests/SettingsStoreTests.swift     MODIFIED: triggerKind test
docs/superpowers/specs/smoke-checklist.md   MODIFIED: single-key manual items
```

---

### Task 1: TriggerKind + SingleKeyTrigger state machine + setting (TDD)

**Files:** Modify `LocalTalk/Core/Types.swift`, `LocalTalk/Services/SettingsStore.swift`, `LocalTalkTests/SettingsStoreTests.swift`; Create `LocalTalk/Services/SingleKeyTrigger.swift`, `LocalTalkTests/SingleKeyTriggerTests.swift`

- [ ] **Step 1: Add `TriggerKind` to `Core/Types.swift`**

```swift
enum TriggerKind: String, Codable, CaseIterable {
    case combo          // the Carbon hotkey (⌃⌥Space etc.)
    case rightOption    // single Right Option key, hold-or-tap
}
```

- [ ] **Step 2: Write failing tests `LocalTalkTests/SingleKeyTriggerTests.swift`**

```swift
import XCTest
@testable import Bulong

final class SingleKeyTriggerTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testTapStartsAndStaysRecording() {
        var trg = SingleKeyTrigger(tapThreshold: 0.25)
        XCTAssertEqual(trg.keyDown(at: at(0)), .start)     // press
        XCTAssertEqual(trg.keyUp(at: at(0.1)), .none)      // quick release = tap-to-start, keep recording
        XCTAssertTrue(trg.isRecording)
    }

    func testSecondTapStops() {
        var trg = SingleKeyTrigger(tapThreshold: 0.25)
        _ = trg.keyDown(at: at(0)); _ = trg.keyUp(at: at(0.1))   // tap → recording
        XCTAssertEqual(trg.keyDown(at: at(1.0)), .none)          // second press (during toggle session)
        XCTAssertEqual(trg.keyUp(at: at(1.1)), .stop)            // release → stop
        XCTAssertFalse(trg.isRecording)
    }

    func testHoldIsPushToTalk() {
        var trg = SingleKeyTrigger(tapThreshold: 0.25)
        XCTAssertEqual(trg.keyDown(at: at(0)), .start)   // press starts
        XCTAssertEqual(trg.keyUp(at: at(0.9)), .stop)    // long hold → stop on release
        XCTAssertFalse(trg.isRecording)
    }

    func testResetClears() {
        var trg = SingleKeyTrigger(tapThreshold: 0.25)
        _ = trg.keyDown(at: at(0)); _ = trg.keyUp(at: at(0.1))  // recording
        trg.reset()
        XCTAssertFalse(trg.isRecording)
        XCTAssertEqual(trg.keyDown(at: at(2)), .start)          // fresh start after reset
    }
}
```

- [ ] **Step 3: Run tests to verify they fail** (SingleKeyTrigger not found).

- [ ] **Step 4: Write `LocalTalk/Services/SingleKeyTrigger.swift`** (exact code from the spec):

```swift
import Foundation

/// Pure hold-or-tap decision for a single-key dictation trigger. No AppKit;
/// timestamps are injected so it is fully unit-testable. Emits a pulse
/// (.start / .stop) at each moment the app should toggle dictation.
struct SingleKeyTrigger {
    enum Action { case start, stop, none }

    var tapThreshold: TimeInterval = 0.25
    private(set) var isRecording = false
    private var downTime: Date?
    private var startedOnThisDown = false

    mutating func keyDown(at t: Date) -> Action {
        downTime = t
        if !isRecording {
            isRecording = true
            startedOnThisDown = true
            return .start
        }
        startedOnThisDown = false   // press during an active toggle session → stops on release
        return .none
    }

    mutating func keyUp(at t: Date) -> Action {
        defer { downTime = nil }
        let held = downTime.map { t.timeIntervalSince($0) } ?? 0
        if startedOnThisDown {
            if held >= tapThreshold {           // HOLD = push-to-talk
                isRecording = false
                return .stop
            }
            return .none                        // TAP-to-start: keep recording
        }
        isRecording = false                     // toggle stop (tap or hold)
        return .stop
    }

    mutating func reset() {
        isRecording = false
        downTime = nil
        startedOnThisDown = false
    }
}
```

- [ ] **Step 5: Run tests to verify they pass.**

- [ ] **Step 6: Add `triggerKind` to `SettingsStore` + a failing test**

Append to `LocalTalkTests/SettingsStoreTests.swift`:
```swift
    @MainActor func testTriggerKindDefaultsComboAndPersists() {
        let s1 = SettingsStore(defaults: defaults)
        XCTAssertEqual(s1.triggerKind, .combo)
        s1.triggerKind = .rightOption
        let s2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(s2.triggerKind, .rightOption)
    }
```
In `SettingsStore`: add `var triggerKind: TriggerKind { didSet { defaults.set(triggerKind.rawValue, forKey: "triggerKind") } }`, initialized in `init` via `TriggerKind(rawValue: defaults.string(forKey: "triggerKind") ?? "") ?? .combo`. Do NOT touch `MigrationService.settingsKeys` (frozen; this is a new Bulong-era key).

- [ ] **Step 7: Run full suite green; commit**

```bash
xcodegen generate && xcodebuild test ... | tail -5   # expect all green (+4 trigger, +1 settings)
git add LocalTalk/Core/Types.swift LocalTalk/Services/SingleKeyTrigger.swift LocalTalk/Services/SettingsStore.swift LocalTalkTests/SingleKeyTriggerTests.swift LocalTalkTests/SettingsStoreTests.swift
git commit -m "feat(hotkey): TriggerKind + pure SingleKeyTrigger hold/tap state machine"
```

---

### Task 2: Right-Option NSEvent monitor + wiring + Settings UI

**Files:** Modify `LocalTalk/Services/HotkeyService.swift`, `LocalTalk/LocalTalkApp.swift`, `LocalTalk/UI/MainWindow/SettingsView.swift`, `docs/superpowers/specs/smoke-checklist.md`

- [ ] **Step 1: Add the monitor to `HotkeyService`** (read the file first). Add stored state + API:

```swift
    // Single-key (Right Option) trigger
    var onSingleKeyAction: ((SingleKeyTrigger.Action) -> Void)?
    private(set) var singleKeyError: String?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var trigger = SingleKeyTrigger()
    private var wasRightOptionDown = false
    private static let rightAlternateMask: UInt = 0x40   // NX_DEVICERALTKEYMASK (Left Option = 0x20)

    func startSingleKeyMonitor() {
        stopSingleKeyMonitor()
        guard AXIsProcessTrusted() else {
            singleKeyError = "Right Option needs Accessibility — grant it above, then reopen Settings."
            return
        }
        singleKeyError = nil
        trigger.reset(); wasRightOptionDown = false
        let handler: (NSEvent) -> Void = { [weak self] event in self?.handleFlags(event) }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged], handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlags(event); return event      // return the event so it isn't swallowed
        }
    }

    func stopSingleKeyMonitor() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
        wasRightOptionDown = false
    }

    func resetSingleKey() { trigger.reset(); wasRightOptionDown = false }

    private func handleFlags(_ event: NSEvent) {
        let down = (event.modifierFlags.rawValue & Self.rightAlternateMask) != 0
        guard down != wasRightOptionDown else { return }   // only real right-option transitions
        wasRightOptionDown = down
        let action = down ? trigger.keyDown(at: Date()) : trigger.keyUp(at: Date())
        if action != .none { onSingleKeyAction?(action) }
    }
```

Add `import AppKit` (for NSEvent) and `import ApplicationServices`/`import AppKit` for `AXIsProcessTrusted` (already available via AppKit). In `unregister()`/deinit path, also call `stopSingleKeyMonitor()`. Note: NSEvent monitor handlers are delivered on the main thread, so `@MainActor` access here is safe — do not wrap in Task.

- [ ] **Step 2: Wire in `AppComposition` (LocalTalkApp.swift)**

In `wire(model:)` (or the existing hotkey-wiring function), after computing the mode, branch on `model.settings.triggerKind`:
```swift
        func applyTrigger() {
            switch model.settings.triggerKind {
            case .combo:
                hotkey.stopSingleKeyMonitor()
                hotkey.register(model.settings.hotkey)          // existing combo path
            case .rightOption:
                hotkey.unregisterPrimaryCombo()                 // add a public method to unregister just the combo (id 1)
                hotkey.onSingleKeyAction = { [weak model] action in
                    guard let model else { return }
                    Task { @MainActor in
                        switch action {
                        case .start, .stop: await model.toggleDictation()  // start pulse: idle→record; stop pulse: record→stop
                        case .none: break
                        }
                    }
                }
                hotkey.startSingleKeyMonitor()
            }
        }
        applyTrigger()
```
- Add `func unregisterPrimaryCombo() { unregisterPrimary() }` (public wrapper) to HotkeyService, or make `unregisterPrimary()` accessible.
- In the existing `onStateChange` handler, on `.idle` and `.failed`, call `hotkey.resetSingleKey()` (so cancel/failure/watchdog resync the trigger).
- Re-run `applyTrigger()` when `settings.triggerKind` changes: the Settings picker sets it; add an observation or call `AppComposition.applyTrigger()` from the Settings control's action. Simplest: expose `static func applyTrigger()` on AppComposition operating on the shared model, and call it from the Settings picker after setting `triggerKind`.
- Keep Escape registered in both modes (unchanged).

- [ ] **Step 3: Settings UI — Trigger choice** (SettingsView.swift, Hotkey SectionCard)

Add above the existing Shortcut/Behavior rows:
```swift
                    row("Trigger") {
                        Picker("", selection: triggerKindBinding) {
                            Text("Key combo").tag(TriggerKind.combo)
                            Text("Right Option").tag(TriggerKind.rightOption)
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
                    }
                    divider
```
- When `.combo`: show the existing Shortcut recorder + Behavior rows (as today).
- When `.rightOption`: hide the recorder; show a caption row: "Tap Right ⌥ to toggle · hold to talk" (`Theme.Fonts.caption`, `textTertiary`), and if `AppComposition.hotkey.singleKeyError != nil`, show it in `Theme.failure`.
- `triggerKindBinding` sets `model.settings.triggerKind` then calls `AppComposition.applyTrigger()`.

- [ ] **Step 4: Build, tests, MANUAL verify (the monitor only works with real keys)**

BUILD/TEST green (49+ prior + new). Then `./script/dev_build.sh` and manually verify (this is essential — the monitor, like the audio tap, is exactly where tests can't reach):
1. Settings → Hotkey → Trigger → **Right Option**. Ensure Accessibility is granted (else the caption shows the grant note).
2. **Tap** Right ⌥ in TextEdit → HUD appears and stays (toggle armed); tap again → transcribes + pastes.
3. **Hold** Right ⌥ → records while held; release → transcribes (push-to-talk).
4. Left ⌥ does nothing; Right ⌥ used inside another shortcut doesn't trigger dictation and still reaches the other app.
5. Switch Trigger back to **Key combo** → ⌃⌥Space works again, Right ⌥ inert.
6. Start a toggle session, press Esc → cancels; next Right ⌥ tap starts fresh (reset worked).

- [ ] **Step 5: Smoke checklist + commit**

Append to `docs/superpowers/specs/smoke-checklist.md` a "## Single-key trigger (Right Option)" section with items 1–6 above (they require a live keyboard, like the HUD/audio items).

```bash
git add LocalTalk/Services/HotkeyService.swift LocalTalk/LocalTalkApp.swift LocalTalk/UI/MainWindow/SettingsView.swift docs/superpowers/specs/smoke-checklist.md
git commit -m "feat(hotkey): Right Option single-key trigger — monitor, wiring, settings"
```

---

## Self-review notes (for the executor)

- **Spec coverage:** state machine + types + setting (T1); monitor + wiring + Settings UI + reset-on-idle + manual checklist (T2). Every spec section maps.
- **Threading:** NSEvent monitors deliver on the main thread — the handler is main-actor-safe; do NOT add a CGEventTap (off-main → the AudioService crash class). If the compiler complains about main-actor isolation in the C-style handler, the closure is a plain Swift closure delivered on main, so `@MainActor`-hop with `Task { @MainActor in … }` only inside the AppComposition callback (as written), not in the monitor handler.
- **Accessibility reuse:** the monitor no-ops silently without `AXIsProcessTrusted()`, so the `singleKeyError` surfacing is REQUIRED (a silent dead trigger is a support nightmare). If macOS turns out to require Input Monitoring for `.flagsChanged` global monitoring on this OS, report it — the fallback is one added permission, documented in the spec.
- **Desync guard:** `resetSingleKey()` on every idle/failed transition keeps the trigger's `isRecording` synced with the app; without it, a cancel would leave the trigger thinking it's still recording.
- **Frozen migration keys:** `triggerKind` is a new Bulong-era key — NOT added to `MigrationService.settingsKeys`.
- Never `git add -A` (repo-root mp3s).
