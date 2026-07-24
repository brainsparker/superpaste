import AppKit
import Combine
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
    private var hostingView: NSHostingView<HUDContentView>?
    private let hudState: HUDState
    private var cancellables = Set<AnyCancellable>()

    init(hudState: HUDState) {
        self.hudState = hudState

        // The working, success, and error layouts have different heights.
        // Refit after published state changes so recovery controls never clip.
        hudState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.resizeToFit()
                }
            }
            .store(in: &cancellables)
    }

    func show() {
        guard panel == nil else {
            resizeToFit()
            return
        }

        // Create panel
        let panel = HUDPanel()

        // Create SwiftUI content
        let contentView = HUDContentView(hudState: hudState)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]

        panel.contentView = hostingView
        self.panel = panel
        self.hostingView = hostingView

        // Position and show
        resizeToFit()
        // The HUD is summoned by a frequently used keyboard shortcut. Show it
        // on the same beat as the key press instead of making the user wait
        // through a decorative entrance.
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hide() {
        guard let panel = panel else { return }

        // Use explicit animation with completion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.panel?.orderOut(nil)
                self?.panel = nil
                self?.hostingView = nil
            }
        }
    }

    private func resizeToFit() {
        guard let panel, let hostingView else { return }

        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }

        panel.setContentSize(fittingSize)
        updatePosition()
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
