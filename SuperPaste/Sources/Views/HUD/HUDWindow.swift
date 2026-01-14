import AppKit
import SwiftUI

/// A floating NSPanel for displaying the HUD
final class HUDPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Configure as floating panel
        level = .floating
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false  // SwiftUI view handles shadow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Ignore mouse events on the panel itself
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Controller for managing the HUD window lifecycle
@MainActor
final class HUDWindowController: ObservableObject {
    private var panel: HUDPanel?
    private var hudState: HUDState

    init(hudState: HUDState) {
        self.hudState = hudState
    }

    func show() {
        guard panel == nil else {
            updatePosition()
            return
        }

        // Create panel
        let panel = HUDPanel()

        // Create SwiftUI content
        let contentView = HUDContentView(hudState: hudState)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]

        panel.contentView = hostingView

        // Size to fit content
        if let fittingSize = hostingView.fittingSize as CGSize? {
            panel.setContentSize(fittingSize)
        }

        self.panel = panel

        // Position and show
        updatePosition()
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel = panel else { return }

        // Use explicit animation with completion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.panel?.orderOut(nil)
                self?.panel = nil
            }
        }
    }

    func updatePosition() {
        guard let panel = panel,
              let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let position = hudState.position

        let origin = position.origin(
            hudSize: panelSize,
            screenFrame: screenFrame,
            margin: 16
        )

        panel.setFrameOrigin(origin)
    }
}
