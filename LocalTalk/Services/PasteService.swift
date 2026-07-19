import AppKit
import ApplicationServices

@MainActor
final class PasteService {
    private static let trustedPromptOption = "AXTrustedCheckOptionPrompt"

    /// AX calls are synchronous mach IPC into the TARGET app; a busy target
    /// (Electron apps under load) can stall the caller up to the default 6s
    /// timeout PER CALL. They run on this queue with a short explicit timeout
    /// so Bulong's main thread — and with it the HUD — can never beachball
    /// on someone else's process.
    private nonisolated static let axQueue = DispatchQueue(label: "com.armageddonvivas.Bulong.ax", qos: .userInitiated)
    private nonisolated static let axTimeoutSeconds: Float = 1.5

    private(set) var targetApp: NSRunningApplication?

    /// Probe injected by the composition root: true while the onboarding
    /// window is up. Dictating there must land in Bulong's own test field,
    /// not the previously-active app.
    var isOnboardingActive: @MainActor () -> Bool = { false }

    /// Most recent frontmost app other than Bulong. With the .window-style
    /// popover, clicking a popover button can make Bulong itself frontmost,
    /// so capture must fall back to the app the user was actually in.
    private var lastExternalApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    var targetAppName: String {
        targetApp?.localizedName ?? "Unknown"
    }

    init() {
        // Seed with whatever app is frontmost at launch so a popover-triggered
        // dictation before any app switch still has a paste target.
        if let frontmost = NSWorkspace.shared.frontmostApplication,
            frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApp = frontmost
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return }
            MainActor.assumeIsolated {
                self?.lastExternalApp = app
            }
        }
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let options = [
            trustedPromptOption: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func captureTarget() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let frontmost, frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            targetApp = frontmost
        } else if isOnboardingActive() {
            // Bulong itself is frontmost with onboarding up: nil target means
            // insert() skips app activation and lands in the focused element
            // (the onboarding test field), not the last external app.
            targetApp = nil
        } else {
            targetApp = lastExternalApp
        }
    }

    func insert(_ text: String, alsoCopy: Bool) async -> InsertionResult {
        defer {
            if alsoCopy {
                Self.setClipboard(text)
            }
        }

        guard Self.isAccessibilityTrusted else {
            Self.setClipboard(text)
            return .clipboardOnly(reason: "grant Accessibility in System Settings to paste automatically")
        }

        if let targetApp, NSWorkspace.shared.frontmostApplication != targetApp {
            targetApp.activate()
            try? await Task.sleep(for: .milliseconds(150))
        }

        switch await axInsert(text) {
        case .inserted:
            return .insertedDirectly
        case .fallBackToCmdV:
            return await pasteViaCmdV(text, preserveClipboard: !alsoCopy)
        case .noEditableFocus:
            // Never blind-paste: Cmd-V into a non-text target can trigger
            // arbitrary app shortcuts. Leave it on the clipboard instead.
            Self.setClipboard(text)
            return .clipboardOnly(reason: "no text field is focused — click one and press ⌘V")
        }
    }

    private enum AXInsertOutcome {
        case inserted
        /// Focus looks like (or might be) a text target, but the direct AX
        /// write isn't supported there — Cmd-V is safe and appropriate.
        case fallBackToCmdV
        /// Focus is positively NOT a text target (button, menu, image, …).
        case noEditableFocus
    }

    private func axInsert(_ text: String) async -> AXInsertOutcome {
        await withCheckedContinuation { continuation in
            Self.axQueue.async {
                continuation.resume(returning: Self.performAXInsert(text))
            }
        }
    }

    private nonisolated static func performAXInsert(_ text: String) -> AXInsertOutcome {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, axTimeoutSeconds)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let focused else {
            // No AX focus at all (or the app timed out): unknowable, so keep
            // the historical Cmd-V behavior rather than regressing apps with
            // broken AX trees.
            return .fallBackToCmdV
        }

        let axElement = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(axElement, axTimeoutSeconds)

        if AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success {
            return .inserted
        }

        return isPositivelyNonEditable(axElement) ? .noEditableFocus : .fallBackToCmdV
    }

    /// True only when the focused element's role clearly identifies a
    /// non-text control. Ambiguity (missing role, web areas, Electron groups)
    /// deliberately returns false — those targets often accept Cmd-V even
    /// though their AX trees say nothing useful.
    private nonisolated static func isPositivelyNonEditable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return false
        }

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return false
        }

        let nonTextRoles: Set<String> = [
            kAXButtonRole, kAXMenuButtonRole, kAXMenuItemRole, kAXMenuRole,
            kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole,
            kAXImageRole, kAXStaticTextRole, kAXToolbarRole, kAXSliderRole,
            kAXTabGroupRole, kAXTableRole, kAXOutlineRole, "AXLink",
            kAXDisclosureTriangleRole,
        ]
        return nonTextRoles.contains(role)
    }

    private func pasteViaCmdV(_ text: String, preserveClipboard: Bool) async -> InsertionResult {
        let pasteboard = NSPasteboard.general
        let savedItems: [NSPasteboardItem] = preserveClipboard
            ? pasteboard.pasteboardItems?.map { item in
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        copy.setData(data, forType: type)
                    }
                }
                return copy
            } ?? []
            : []

        Self.setClipboard(text)

        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        if preserveClipboard, !savedItems.isEmpty {
            try? await Task.sleep(for: .milliseconds(400))
            pasteboard.clearContents()
            pasteboard.writeObjects(savedItems)
        }

        return .pastedViaCmdV
    }

    private static func setClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
