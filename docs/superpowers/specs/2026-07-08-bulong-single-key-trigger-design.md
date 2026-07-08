# Bulong Single-Key Trigger (Right Option) — Design

Date: 2026-07-08
Status: approved by Armageddon (Right Option, hold-or-tap). Surfaced during the test drive.

## Context and decisions (locked)

- Add a **single-key dictation trigger** alongside the existing Carbon combo hotkey (⌃⌥Space). The combo path stays; users choose their trigger in Settings.
- **Trigger key:** the **Right Option** key specifically (virtual key code 61 / `kVK_RightOption`), so Left Option stays free for normal accent/shortcut use.
- **Behavior — hold OR tap, one key:** press Right ⌥ → start listening. Release **quickly** (a tap, < ~250 ms) → keep recording; tap again to stop (toggle). **Hold** it (≥ threshold) → record only while held, transcribe on release (push-to-talk). One key does both; the hold duration decides.
- **Permission:** reuse the **Accessibility** permission already required for auto-paste. Observing modifier keys via a global `NSEvent` monitor requires the app to be Accessibility-trusted — which it already is. NO new permission if this holds; if macOS unexpectedly requires Input Monitoring for the monitor, surface it and add that one permission (documented fallback).
- **Threading safety (learned from the AudioService crash):** use `NSEvent.addGlobalMonitorForEvents` + `addLocalMonitorForEvents`, whose handlers are delivered on the **main thread** — so the callback is main-actor-safe. Do NOT use a `CGEventTap` (runs on a separate thread → the exact `@Sendable`/executor-assertion class of bug that just crashed the app).

## Architecture

Two parts: a pure, unit-testable **hold/tap state machine**, and the **NSEvent modifier monitor** that feeds it. Both live in the existing `HotkeyService` (it owns hotkeys), plus a Settings choice and composition wiring.

### 1. `SingleKeyTrigger` — pure hold/tap state machine (new type, testable)

A struct/class with injectable `now` and a `tapThreshold` (default 0.25 s). It consumes raw key-down/up events with timestamps and emits **trigger pulses** — one at each start moment and each stop moment — via a callback. It never touches AppKit.

```swift
struct SingleKeyTrigger {
    var tapThreshold: TimeInterval = 0.25
    private(set) var isRecording = false
    private var downTime: Date?
    private var startedOnThisDown = false

    /// Returns .start / .stop / .none for each event; caller pulses the app.
    enum Action { case start, stop, none }

    mutating func keyDown(at t: Date) -> Action {
        downTime = t
        if !isRecording { isRecording = true; startedOnThisDown = true; return .start }
        startedOnThisDown = false     // a press during an active toggle session → will stop on release
        return .none
    }

    mutating func keyUp(at t: Date) -> Action {
        defer { downTime = nil }
        let held = downTime.map { t.timeIntervalSince($0) } ?? 0
        if startedOnThisDown {
            if held >= tapThreshold { isRecording = false; return .stop }  // HOLD = push-to-talk
            return .none                                                   // TAP-to-start = keep recording
        } else {
            isRecording = false; return .stop                             // toggle stop (tap or hold)
        }
    }

    mutating func reset() { isRecording = false; downTime = nil; startedOnThisDown = false }
}
```

Truth table this must satisfy (the tests): tap→start keeps recording; a second tap stops; a single long hold starts on down and stops on release; `reset()` clears everything (used when the app returns to idle by cancel/failure/watchdog so the trigger can't desync).

### 2. Modifier monitor in `HotkeyService`

- New API on `HotkeyService`: `enable/disableSingleKey(_ onAction: @escaping (SingleKeyTrigger.Action) -> Void)` (or a stored `onSingleKeyAction` callback + `startSingleKeyMonitor()/stopSingleKeyMonitor()`), and `resetSingleKey()`.
- Install `NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged])` AND `addLocalMonitorForEvents(matching: [.flagsChanged]) { … ; return $0 }` (local so it also works when Bulong itself is frontmost; the local monitor must return the event to not swallow it). Store both tokens; remove them on disable/deinit.
- In the handler (main thread): detect RIGHT option specifically via the device-dependent right-alternate bit — `let rightOptionDown = (event.modifierFlags.rawValue & 0x40) != 0` (NX_DEVICERALTKEYMASK = 0x40; Left Option is 0x20). Keep a `wasRightOptionDown` bool; a false→true transition is a key-down, true→false is a key-up. This reads right-vs-left directly from the flags, so it's correct even when Left Option is also held. Feed the transition's timestamp to `keyDown(at:)`/`keyUp(at:)` and forward the returned `Action`.
- Only act on right-alternate transitions; ignore flagsChanged for any other modifier and ignore events where the right-alternate bit is unchanged (auto-repeat / other-key noise).
- Guard on Accessibility: only start the monitor when `AXIsProcessTrusted()`; if not trusted, set a `registrationError`-style message directing the user to grant Accessibility. (The monitor silently no-ops without trust, so this must be surfaced.)

### 3. Settings — trigger choice

- `SettingsStore` gains `triggerKind: TriggerKind` (`.combo` | `.rightOption`), persisted, default `.combo` (unchanged behavior for existing users).
- Settings → Hotkey section: a control to choose **Trigger** — "Key combo (⌃⌥Space)" showing the existing recorder, or "Right Option" showing a short hint ("Tap to toggle · hold to talk"). When `.rightOption`, the combo recorder is hidden/disabled and the single-key hint + an Accessibility-required note (if not trusted) shows.
- `TriggerKind` added to `Core/Types.swift`. `MigrationService.settingsKeys` stays FROZEN (this is a new Bulong-era key — do not add it there).

### 4. Composition wiring (`AppComposition`)

- When `settings.triggerKind == .rightOption`: call `hotkey.startSingleKeyMonitor` with a callback that maps `.start`/`.stop` → `model.toggleDictation()` (start pulse when idle → records; stop pulse when recording → stops). Disable the Carbon combo while single-key is active (unregister the primary combo so both don't fire); keep Escape-cancel registered.
- When `.combo`: stop the single-key monitor, register the combo as today.
- On `model.onStateChange` → `.idle`/`.failed`, call `hotkey.resetSingleKey()` so a cancel/failure/watchdog resyncs the trigger's `isRecording` with reality.
- Switching the setting live re-runs this wiring (re-read on change).

## Error handling / edge cases

- **Not Accessibility-trusted:** single-key monitor no-ops; Settings shows "Right Option needs Accessibility — grant it above." The combo path is unaffected.
- **Desync:** any app-side end of dictation (Esc, too-short, failure, watchdog, manual stop via popover) calls `resetSingleKey()`, so the next Right-Option press starts fresh.
- **Right Option used in another app's shortcut:** the monitor observes but does not consume the event (global monitors can't consume; the local monitor returns it), so other apps still receive Right ⌥ normally. A rare overlap is tolerated.
- **Auto-repeat / rapid presses:** only true down/up transitions of keyCode 61 drive the state machine; repeats are ignored via the last-known-state tracking.

## Testing

- **`SingleKeyTrigger` (pure, TDD):** tap→start returns `.start` and stays recording; second tap `keyDown` returns `.none`, its `keyUp` returns `.stop`; single hold: `keyDown`→`.start`, `keyUp` after ≥threshold →`.stop`; hold below threshold on the FIRST press keeps recording (tap semantics); `reset()` returns to idle; injected `now`/timestamps drive all timing. No AppKit.
- **SettingsStore:** `triggerKind` defaults `.combo`, persists across instances.
- **Manual (only real keys exercise the monitor — like the audio tap, this is where reality differs from tests):** with `.rightOption` selected and Accessibility granted — tap Right ⌥ → HUD appears and stays (toggle); tap again → transcribes + pastes; hold Right ⌥ → records while held, transcribes on release; Left ⌥ and Right ⌥ inside other shortcuts do NOT trigger; revoke Accessibility → Settings shows the grant note and the trigger is inert. Add these to the smoke checklist.

## Out of scope

- Other single keys (Fn, right-Command, double-tap) — Right Option only for v1; `TriggerKind` is an enum so more can be added later.
- Consuming/blocking the Right ⌥ event from other apps (not needed; observe-only).
- No changes to transcription, HUD, history, licensing, or the combo hotkey path beyond the coexistence wiring.
