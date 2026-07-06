import AppKit
import SwiftUI

@MainActor
final class HUDPanelController {
    private var panel: NSPanel?
    private var dragStartOrigin: NSPoint?

    func show<Content: View>(@ViewBuilder content: () -> Content) {
        let panel = panel ?? makePanel()
        let wasVisible = panel.isVisible
        panel.contentView = NSHostingView(rootView: content())

        if !wasVisible {
            position(panel)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        persistPosition()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    func drag(to translation: CGSize) {
        guard let panel else { return }
        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
        }
        guard let dragStartOrigin else { return }
        panel.setFrameOrigin(NSPoint(
            x: dragStartOrigin.x + translation.width,
            y: dragStartOrigin.y - translation.height
        ))
    }

    func finishDrag() {
        persistPosition()
        dragStartOrigin = nil
    }

    func persistPosition() {
        guard let panel, let screen = panel.screen else { return }
        UserDefaults.standard.set(
            NSStringFromPoint(panel.frame.origin),
            forKey: originKey(for: screen)
        )
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 84),
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

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        guard let screen else { return }

        if let saved = UserDefaults.standard.string(forKey: originKey(for: screen)) {
            let origin = NSPointFromString(saved)
            panel.setFrameOrigin(clamped(origin, for: panel, on: screen))
            return
        }

        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.minY + 24
        ))
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
