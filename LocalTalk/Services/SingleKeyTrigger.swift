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

    init(tapThreshold: TimeInterval = 0.25) {
        self.tapThreshold = tapThreshold
    }

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
        // A release with no matching keyDown (the trigger was reset while the
        // key was physically held) must be inert — a stray .stop pulse here
        // would toggle dictation back ON from idle.
        guard downTime != nil else { return .none }
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
