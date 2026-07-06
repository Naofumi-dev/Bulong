import Carbon.HIToolbox
import Foundation

@MainActor
final class HotkeyService {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?
    private(set) var registrationError: String?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x4C544B31

    func register(_ spec: HotkeySpec) {
        unregister()

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

                DispatchQueue.main.async {
                    if kind == UInt32(kEventHotKeyPressed) {
                        service.onPressed?()
                    } else if kind == UInt32(kEventHotKeyReleased) {
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

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
