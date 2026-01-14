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

    private var autoDismissTask: Task<Void, Never>?
    private var progressAnimationTask: Task<Void, Never>?

    // MARK: - Stage Transitions

    func startGathering() {
        cancelTasks()
        isVisible = true
        stage = .gathering
        currentPhrase = HUDPhrases.randomGathering()

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

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            progress = 1.0
        }

        // Play sound if enabled
        if playSoundOnReady {
            NSSound.beep()
        }

        // Auto-dismiss after 5 seconds
        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismiss()
            }
        }
    }

    func showError(_ message: String) {
        cancelTasks()
        stage = .error(message)
        currentPhrase = HUDPhrases.randomError()
        progress = 0.0

        // Auto-dismiss error after 5 seconds
        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
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
                stage = .gathering
                progress = 0.0
                currentPhrase = ""
            }
        }
    }

    // MARK: - Private

    private func cancelTasks() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        progressAnimationTask?.cancel()
        progressAnimationTask = nil
    }
}
