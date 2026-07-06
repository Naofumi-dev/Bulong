import Carbon.HIToolbox
import Foundation

final class GlobalHotKey {
    private var eventHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    deinit {
        unregister()
    }

    func registerDefault(handler: @escaping () -> Void) throws {
        try register(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey | optionKey),
            handler: handler
        )
    }

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) throws {
        unregister()
        self.handler = handler

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                hotKey.fire()
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard installStatus == noErr else {
            throw GlobalHotKeyError(action: "install hotkey handler", status: installStatus)
        }

        var hotKeyID = EventHotKeyID(signature: fourCharacterCode("LoTk"), id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKey
        )

        guard registerStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            throw GlobalHotKeyError(action: "register Control+Option+Space", status: registerStatus)
        }
    }

    func unregister() {
        if let eventHotKey {
            UnregisterEventHotKey(eventHotKey)
            self.eventHotKey = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func fire() {
        DispatchQueue.main.async { [handler] in
            handler?()
        }
    }
}

private func fourCharacterCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { result, character in
        (result << 8) + OSType(character)
    }
}

struct GlobalHotKeyError: LocalizedError {
    let action: String
    let status: OSStatus

    var errorDescription: String? {
        "Could not \(action) (OSStatus \(status))"
    }
}
