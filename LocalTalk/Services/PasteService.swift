import AppKit
import ApplicationServices

@MainActor
final class PasteService {
    private static let trustedPromptOption = "AXTrustedCheckOptionPrompt"

    private(set) var targetApp: NSRunningApplication?

    var targetAppName: String {
        targetApp?.localizedName ?? "Unknown"
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
        targetApp = NSWorkspace.shared.frontmostApplication
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

        if axInsert(text) {
            return .insertedDirectly
        }

        return await pasteViaCmdV(text, preserveClipboard: !alsoCopy)
    }

    private func axInsert(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let focused else {
            return false
        }

        let axElement = focused as! AXUIElement
        return AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success
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
