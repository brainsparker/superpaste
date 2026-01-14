import SwiftUI
import Combine

/// Manages the HUD window lifecycle based on HUDState changes
@MainActor
final class HUDManager: ObservableObject {
    private var windowController: HUDWindowController?
    private var hudState: HUDState
    private var cancellables = Set<AnyCancellable>()

    init(hudState: HUDState) {
        self.hudState = hudState
        self.windowController = HUDWindowController(hudState: hudState)
        setupBindings()
    }

    private func setupBindings() {
        // React to visibility changes
        hudState.$isVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                if isVisible {
                    self?.windowController?.show()
                } else {
                    self?.windowController?.hide()
                }
            }
            .store(in: &cancellables)

        // Note: Position changes are applied when the HUD is shown next time.
        // The windowController reads the position from hudState.position when showing.
    }

    /// Call this to set up keyboard monitoring for HUD dismissal
    func setupKeyboardMonitoring() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }

            Task { @MainActor in
                // If HUD is visible in ready or error state, dismiss on any key press
                if self.hudState.isVisible &&
                   (self.hudState.stage == .ready || self.hudState.stage.isError) {
                    self.hudState.dismiss()
                }
            }
        }
    }
}
