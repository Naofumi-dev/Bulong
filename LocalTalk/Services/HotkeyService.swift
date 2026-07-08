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

    // Single-key (Right Option) trigger
    var onSingleKeyAction: ((SingleKeyTrigger.Action) -> Void)?
    private(set) var singleKeyError: String?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var trigger = SingleKeyTrigger()
    private var wasRightOptionDown = false
    private static let rightAlternateMask: UInt = 0x40   // NX_DEVICERALTKEYMASK (Left Option = 0x20)

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
            singleKeyError = "Right Option needs Accessibility — grant it in Permissions below; it arms automatically."
            return
        }
        singleKeyError = nil
        trigger.reset()
        wasRightOptionDown = false
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
        wasRightOptionDown = false
    }

    func resetSingleKey() {
        trigger.reset()
        wasRightOptionDown = false
    }

    private func handleFlags(_ event: NSEvent) {
        let down = (event.modifierFlags.rawValue & Self.rightAlternateMask) != 0
        guard down != wasRightOptionDown else { return }   // only real right-option transitions
        wasRightOptionDown = down
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
