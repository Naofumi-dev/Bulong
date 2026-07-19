import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

@MainActor @Observable
final class HotkeyService {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?
    var onEscapePressed: (() -> Void)?
    private(set) var registrationError: String?

    private var hotKeyRef: EventHotKeyRef?
    private var escapeHotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x4C544B31

    // Single-key trigger (user picks which key; composition sets the mask)
    var onSingleKeyAction: ((SingleKeyTrigger.Action) -> Void)?
    private(set) var singleKeyError: String?
    /// Device-dependent modifier bit to watch. Set by AppComposition.applyTrigger
    /// from the user's `SingleKeyChoice` before `startSingleKeyMonitor()`.
    /// Defaults to Right Option (0x40).
    var singleKeyMask: UInt = 0x40
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var singleKeyHotKeyRef: EventHotKeyRef?
    private var trigger = SingleKeyTrigger()
    private var wasSingleKeyDown = false

    func register(_ spec: HotkeySpec) {
        unregisterPrimary()
        ensureHandlerInstalled()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            spec.keyCode,
            spec.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        registrationError = status == noErr
            ? nil
            : "Couldn't register \(spec.displayString). Another app may be using it."
    }

    func registerEscape(onPress: @escaping () -> Void) {
        unregisterEscape()
        onEscapePressed = onPress
        ensureHandlerInstalled()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 2)
        let status = RegisterEventHotKey(
            53,
            0,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &escapeHotKeyRef
        )

        if status != noErr {
            onEscapePressed = nil
        }
    }

    func unregisterEscape() {
        if let escapeHotKeyRef {
            UnregisterEventHotKey(escapeHotKeyRef)
            self.escapeHotKeyRef = nil
        }
        onEscapePressed = nil
    }

    func unregister() {
        unregisterPrimary()
        unregisterEscape()
        stopSingleKeyMonitor()
        stopSingleKeyHotKey()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    /// Public wrapper so composition can unregister just the combo (id 1)
    /// when switching to the single-key trigger, keeping Escape (id 2) live.
    func unregisterPrimaryCombo() {
        unregisterPrimary()
    }

    func startSingleKeyMonitor() {
        stopSingleKeyMonitor()
        guard AXIsProcessTrusted() else {
            singleKeyError = "This trigger key needs Accessibility — grant it in Permissions below; it arms automatically."
            return
        }
        singleKeyError = nil
        trigger.reset()
        wasSingleKeyDown = false
        // NSEvent monitor handlers are delivered on the MAIN thread, so the
        // @MainActor `handleFlags` is reached via `MainActor.assumeIsolated`
        // (matching PasteService's activation observer) — no Task hop, so the
        // hold/tap timing stays exact and we avoid the off-main crash class.
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlags(event) }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged], handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlags(event) }
            return event      // return the event so it isn't swallowed
        }
    }

    func stopSingleKeyMonitor() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
        wasSingleKeyDown = false
    }

    /// Regular single keys (F8 etc.) register as a zero-modifier Carbon hotkey
    /// — global, no Accessibility needed. Press/release edges feed the same
    /// hold-or-tap trigger as the modifier path; the `wasSingleKeyDown` guard
    /// swallows Carbon's auto-repeat presses so holding never re-toggles.
    func registerSingleKey(keyCode: UInt32) {
        stopSingleKeyHotKey()
        ensureHandlerInstalled()
        singleKeyError = nil
        trigger.reset()
        wasSingleKeyDown = false

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 3)
        let status = RegisterEventHotKey(
            keyCode,
            0,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &singleKeyHotKeyRef
        )

        if status != noErr {
            singleKeyError = "Couldn't register that key. Another app may be using it."
        }
    }

    func stopSingleKeyHotKey() {
        if let singleKeyHotKeyRef {
            UnregisterEventHotKey(singleKeyHotKeyRef)
            self.singleKeyHotKeyRef = nil
        }
        wasSingleKeyDown = false
    }

    /// Clears the hold/tap decision state WITHOUT touching `wasSingleKeyDown`:
    /// that flag tracks the PHYSICAL key and is the only thing swallowing
    /// Carbon auto-repeat presses. Zeroing it mid-hold would let the next
    /// auto-repeat register as a fresh press — restarting dictation right
    /// after an Escape-cancel, or retry-looping a failed start while held.
    func resetSingleKey() {
        trigger.reset()
    }

    private func handleFlags(_ event: NSEvent) {
        handleSingleKeyEdge(down: (event.modifierFlags.rawValue & singleKeyMask) != 0)
    }

    fileprivate func handleSingleKeyEdge(down: Bool) {
        guard down != wasSingleKeyDown else { return }   // only real transitions of the chosen key
        wasSingleKeyDown = down
        let action = down ? trigger.keyDown(at: Date()) : trigger.keyUp(at: Date())
        if action != .none { onSingleKeyAction?(action) }
    }

    private func ensureHandlerInstalled() {
        guard handlerRef == nil else { return }
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                let service = Unmanaged<HotkeyService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                let kind = GetEventKind(event)
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return noErr }

                DispatchQueue.main.async {
                    if hotKeyID.id == 2, kind == UInt32(kEventHotKeyPressed) {
                        service.onEscapePressed?()
                    } else if hotKeyID.id == 1, kind == UInt32(kEventHotKeyPressed) {
                        service.onPressed?()
                    } else if hotKeyID.id == 1, kind == UInt32(kEventHotKeyReleased) {
                        service.onReleased?()
                    } else if hotKeyID.id == 3 {
                        service.handleSingleKeyEdge(down: kind == UInt32(kEventHotKeyPressed))
                    }
                }

                return noErr
            },
            2,
            &eventTypes,
            selfPtr,
            &handlerRef
        )
    }

    private func unregisterPrimary() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}
