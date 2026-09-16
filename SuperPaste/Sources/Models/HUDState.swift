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

enum HUDRecoveryAction: Equatable {
    case openSettings
    case screenPermission
    case accessibilityPermission
    case retry
    case copyResponse

    var title: String {
        switch self {
        case .screenPermission:
            return "Screen Recording Settings"
        case .accessibilityPermission:
            return "Accessibility Settings"
        case .openSettings:
            return "Open Settings"
        case .retry:
            return "Try Again"
        case .copyResponse:
            return "Copy Response"
        }
    }

    var icon: String {
        switch self {
        case .openSettings, .screenPermission, .accessibilityPermission:
            return "gear"
        case .retry:
            return "arrow.clockwise"
        case .copyResponse:
            return "doc.on.doc"
        }
    }
}

/// Observable state for the HUD
@MainActor
final class HUDState: ObservableObject {
    @Published var stage: HUDStage = .gathering
    @Published var currentPhrase: String = ""
    @Published var secondaryPhrase: String?
    @Published var recoveryAction: HUDRecoveryAction?
    @Published var isVisible: Bool = false

    @AppStorage("hudPosition") var position: HUDPosition = .topRight
    @AppStorage("playSoundOnReady") var playSoundOnReady: Bool = false

    /// Invoked when the user cancels from the HUD (✕ button). Set by AppState.
    var onCancel: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onScreenPermission: (() -> Void)?
    var onAccessibilityPermission: (() -> Void)?
    @Published private(set) var lastFailure: PasteFailure?
    var onRetry: (() -> Void)?
    var onCopyResponse: (() -> Void)?

    private var autoDismissTask: Task<Void, Never>?
    private var secondaryPhraseTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    // MARK: - Stage Transitions

    func startGathering() {
        cancelTasks()
        isVisible = true
        stage = .gathering
        currentPhrase = "Reading this window…"
        secondaryPhrase = nil
        recoveryAction = nil
        announce("SuperPaste is working")
    }

    func startThinking() {
        stage = .thinking
        currentPhrase = "Writing your reply…"
        secondaryPhrase = nil
        recoveryAction = nil

        // Most requests finish quickly. Save the playful copy for a wait long
        // enough that a little reassurance is useful instead of distracting.
        secondaryPhraseTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled && stage == .thinking else { return }
            await MainActor.run {
                secondaryPhrase = HUDPhrases.randomSlowThinking()
            }
        }
    }

    func showReady() {
        cancelTasks()
        stage = .ready
        currentPhrase = "Pasted"
        secondaryPhrase = "Right where you left off."
        recoveryAction = nil
        announce("Response pasted")

        // Play sound if enabled
        if playSoundOnReady {
            NSSound.beep()
        }

        // Auto-paste fires immediately; the confirmation only needs a beat.
        autoDismissTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismiss()
            }
        }
    }

    func showError(_ failure: PasteFailure) {
        lastFailure = failure
        let message = failure.message
        cancelTasks()
        isVisible = true
        stage = .error(message)
        currentPhrase = "Couldn't paste"
        secondaryPhrase = nil
        recoveryAction = failure.recovery
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

    /// Lets people confirm the bubble's placement and personality without
    /// spending a request or capturing their screen.
    func preview() {
        cancelTasks()
        isVisible = true
        stage = .thinking
        currentPhrase = "Writing your reply…"
        secondaryPhrase = HUDPhrases.randomSlowThinking()
        recoveryAction = nil

        previewTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled && stage == .thinking else { return }
            await MainActor.run {
                showReady()
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
                currentPhrase = ""
                secondaryPhrase = nil
                recoveryAction = nil
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
        secondaryPhraseTask?.cancel()
        secondaryPhraseTask = nil
        previewTask?.cancel()
        previewTask = nil
    }

}
