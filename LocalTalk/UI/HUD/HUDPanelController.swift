import AppKit
import SwiftUI

/// The HUD is clicked while another app is frontmost (non-activating panel), so
/// the first click must land on the cancel button instead of being swallowed as
/// window activation.
@MainActor
private final class HUDHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class HUDPanelController {
    private let panelSize = HUDView.hudSize
    private var panel: NSPanel?
    private var hostingView: NSView?
    private var dragAnchor: (mouse: NSPoint, origin: NSPoint)?
    /// Bumped by every show()/hide(); a hide fade's completion only orders the
    /// panel out if its generation is still current, so a show() landing inside
    /// the 0.16s fade can't be snuffed by the stale completion.
    private var fadeGeneration = 0

    func show<Content: View>(@ViewBuilder content: () -> Content) {
        let panel = panel ?? makePanel()
        // Build the hosting view ONCE. Replacing contentView on every state
        // transition tears down @State (hover, wave smoothing) mid-display;
        // the root view observes the model, so one view tracks all states.
        // (NSPanel auto-creates a placeholder contentView, so we track our own.)
        if hostingView == nil {
            let host = HUDHostingView(rootView: content())
            hostingView = host
            panel.contentView = host
        }
        dragAnchor = nil
        fadeGeneration += 1
        let wasVisible = panel.isVisible

        if !wasVisible {
            let targetOrigin = origin(for: panel)
            panel.alphaValue = 0
            panel.setFrameOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y - 10))
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(targetOrigin)
            }
        } else {
            panel.orderFrontRegardless()
            if panel.alphaValue < 1 {
                // A hide fade is in flight; rescue the panel back to full presence.
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1
                    panel.animator().setFrameOrigin(origin(for: panel))
                }
            }
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        dragAnchor = nil
        fadeGeneration += 1
        let generation = fadeGeneration
        let startOrigin = panel.frame.origin
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(NSPoint(x: startOrigin.x, y: startOrigin.y - 8))
        } completionHandler: {
            Task { @MainActor [weak self] in
                // A show() that landed during the fade owns the panel now.
                guard let self, generation == self.fadeGeneration else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                panel.setFrameOrigin(startOrigin)
            }
        }
    }

    /// Screen-space drag: the SwiftUI gesture is only a begin/change/end signal.
    /// Its translation is measured in a space anchored to the moving window (a
    /// jitter feedback loop), so the real delta comes from `NSEvent.mouseLocation`
    /// against an anchor captured at drag start.
    func dragChanged() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let anchor = dragAnchor ?? (mouse: mouse, origin: panel.frame.origin)
        dragAnchor = anchor
        panel.setFrameOrigin(NSPoint(
            x: anchor.origin.x + (mouse.x - anchor.mouse.x),
            y: anchor.origin.y + (mouse.y - anchor.mouse.y)
        ))
    }

    func finishDrag() {
        persistPosition()
        dragAnchor = nil
    }

    /// Persisting ONLY on drag end means a saved origin always reflects explicit
    /// user intent — never an incidental re-save on hide.
    private func persistPosition() {
        guard let panel, let screen = panel.screen else { return }
        UserDefaults.standard.set(
            NSStringFromPoint(panel.frame.origin),
            forKey: originKey(for: screen)
        )
    }

    /// Forgets user-dragged origins so a freshly picked position preset takes effect.
    func clearSavedPositions() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("hudOrigin-") {
            defaults.removeObject(forKey: key)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        self.panel = panel
        return panel
    }

    private func origin(for panel: NSPanel) -> NSPoint {
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        guard let screen else { return panel.frame.origin }

        if let saved = UserDefaults.standard.string(forKey: originKey(for: screen)) {
            let origin = NSPointFromString(saved)
            return clamped(origin, for: panel, on: screen)
        }

        let frame = screen.visibleFrame
        switch AppComposition.settings.hudPosition {
        case .bottomCenter:
            return NSPoint(x: frame.midX - panelSize.width / 2, y: frame.minY + 24)
        case .topRight:
            return NSPoint(x: frame.maxX - panelSize.width - 24, y: frame.maxY - panelSize.height - 24)
        case .nearNotch:
            return NSPoint(x: frame.midX - panelSize.width / 2, y: frame.maxY - panelSize.height - 10)
        }
    }

    private func clamped(_ origin: NSPoint, for panel: NSPanel, on screen: NSScreen) -> NSPoint {
        let frame = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        return NSPoint(
            x: min(max(origin.x, frame.minX), frame.maxX - panel.frame.width),
            y: min(max(origin.y, frame.minY), frame.maxY - panel.frame.height)
        )
    }

    private func originKey(for screen: NSScreen) -> String {
        "hudOrigin-\(screen.localizedName)"
    }
}
