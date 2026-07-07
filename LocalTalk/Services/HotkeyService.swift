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
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
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
