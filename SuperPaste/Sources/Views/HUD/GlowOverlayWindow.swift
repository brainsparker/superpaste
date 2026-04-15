import AppKit
import SwiftUI

/// A full-screen, click-through overlay window that displays the glow border effect.
final class GlowOverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver  // Above everything
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true  // Fully click-through
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Controller that manages the glow overlay window lifecycle.
@MainActor
final class GlowOverlayController {
    private var panel: GlowOverlayPanel?
    private let hudState: HUDState

    init(hudState: HUDState) {
        self.hudState = hudState
    }

    func show() {
        guard panel == nil, let screen = NSScreen.main else { return }

        let panel = GlowOverlayPanel(screen: screen)

        let glowView = GlowBorderView(hudState: hudState)
        let hostingView = NSHostingView(rootView: glowView)
        hostingView.frame = panel.contentView?.bounds ?? screen.frame
        hostingView.autoresizingMask = [.width, .height]

        panel.contentView = hostingView
        panel.setFrame(screen.frame, display: true)

        self.panel = panel

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel = panel else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.panel?.orderOut(nil)
                self?.panel = nil
            }
        }
    }
}
