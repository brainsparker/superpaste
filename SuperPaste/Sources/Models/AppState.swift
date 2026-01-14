import SwiftUI
import Combine

/// Central app state that coordinates all services and the processing pipeline
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: String?

    // MARK: - Services

    let hotkeyService = HotkeyService.shared
    let contextService = ContextService.shared
    let clipboardService = ClipboardService.shared
    let llmService = LLMService.shared

    // MARK: - HUD State

    let hudState = HUDState()

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var processingTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        setupHotkeySubscription()
    }

    // MARK: - Setup

    func setup() {
        hotkeyService.register()
    }

    private func setupHotkeySubscription() {
        hotkeyService.hotkeyTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleHotkeyTrigger()
            }
            .store(in: &cancellables)
    }

    // MARK: - Hotkey Handler

    private func handleHotkeyTrigger() {
        // If already processing, cancel and restart
        if isProcessing {
            processingTask?.cancel()
            hudState.dismiss()
        }

        // Start the processing pipeline
        processingTask = Task {
            await processPipeline()
        }
    }

    // MARK: - Processing Pipeline

    private func processPipeline() async {
        isProcessing = true
        lastError = nil

        // Stage 1: Gathering context
        hudState.startGathering()

        // Small delay to show gathering stage
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else {
            isProcessing = false
            return
        }

        // Capture context
        let context = contextService.capture()

        // Stage 2: Thinking (calling LLM)
        hudState.startThinking()

        do {
            // Call LLM API
            let response = try await llmService.process(context: context)

            guard !Task.isCancelled else {
                isProcessing = false
                return
            }

            // Write response to clipboard
            clipboardService.write(response)

            // Stage 3: Ready
            hudState.showReady()

        } catch let error as LLMService.LLMError {
            guard !Task.isCancelled else {
                isProcessing = false
                return
            }

            lastError = error.errorDescription
            hudState.showError(error.userFriendlyMessage)

        } catch {
            guard !Task.isCancelled else {
                isProcessing = false
                return
            }

            lastError = error.localizedDescription
            hudState.showError("Something went wrong")
        }

        isProcessing = false
    }

    // MARK: - Manual Actions

    /// Manually dismiss the HUD
    func dismissHUD() {
        processingTask?.cancel()
        hudState.dismiss()
        isProcessing = false
    }
}
