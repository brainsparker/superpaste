import AppKit
import SwiftUI

/// Stage of the HUD processing
enum HUDStage: Equatable {
    case gathering
    case thinking
    case ready
    case error(String)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var isWorking: Bool {
        self == .gathering || self == .thinking
    }
}

/// Observable state for the HUD
@MainActor
final class HUDState: ObservableObject {
    @Published var stage: HUDStage = .gathering
    @Published var progress: Double = 0.0
    @Published var currentPhrase: String = ""
    @Published var isVisible: Bool = false

    @AppStorage("hudPosition") var position: HUDPosition = .topRight
    @AppStorage("playSoundOnReady") var playSoundOnReady: Bool = false

    /// Invoked when the user cancels from the HUD (✕ button). Set by AppState.
    var onCancel: (() -> Void)?

    private var autoDismissTask: Task<Void, Never>?
    private var progressAnimationTask: Task<Void, Never>?

    // MARK: - Stage Transitions

    func startGathering() {
        cancelTasks()
        isVisible = true
        stage = .gathering
        currentPhrase = HUDPhrases.randomGathering()
        announce("SuperPaste is working")

        withAnimation(.easeOut(duration: 0.3)) {
            progress = 0.25
        }
    }

    func startThinking() {
        stage = .thinking
        currentPhrase = HUDPhrases.randomThinking()

        // Animate progress from 25% to 90%
        withAnimation(.easeOut(duration: 0.5)) {
            progress = 0.6
        }

        // Continue pulsing progress while thinking
        progressAnimationTask = Task {
            while !Task.isCancelled && stage == .thinking {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled && stage == .thinking else { break }

                // Rotate phrase
                await MainActor.run {
                    currentPhrase = HUDPhrases.randomThinking()
                }

                // Pulse progress between 60% and 90%
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        progress = progress < 0.75 ? 0.9 : 0.6
                    }
                }
            }
        }
    }

    func showReady() {
        cancelTasks()
        stage = .ready
        currentPhrase = HUDPhrases.randomReady()
        announce("Response pasted")

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            progress = 1.0
        }

        // Play sound if enabled
        if playSoundOnReady {
            NSSound.beep()
        }

        // Auto-dismiss after 1.5 seconds (auto-paste fires immediately, brief confirmation is enough)
        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismiss()
            }
        }
    }

    func showError(_ message: String) {
        cancelTasks()
        isVisible = true
        stage = .error(message)
        currentPhrase = HUDPhrases.randomError(context: message)
        progress = 0.0
        announce("SuperPaste error: \(message)")

        // Errors stay long enough to actually be read (slow readers, screen
        // magnifier users). A click dismisses them earlier.
        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismiss()
            }
        }
    }

    func dismiss() {
        cancelTasks()
        withAnimation(.easeOut(duration: 0.2)) {
            isVisible = false
        }

        // Reset state after animation
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            await MainActor.run {
                guard !isVisible else { return } // a newer run took over the HUD
                stage = .gathering
                progress = 0.0
                currentPhrase = ""
            }
        }
    }

    // MARK: - Private

    /// Blind users otherwise get zero feedback for the entire core flow —
    /// the HUD is purely visual. Announce the transitions that matter.
    private func announce(_ message: String) {
        let element: Any = NSApp.mainWindow ?? NSApp as Any
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func cancelTasks() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        progressAnimationTask?.cancel()
        progressAnimationTask = nil
    }
}
