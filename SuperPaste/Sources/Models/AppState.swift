import SwiftUI
import Combine

/// Main window state machine
enum MainWindowState: Equatable {
    case permissionRequired
    case apiKeyRequired
    case ready
}

/// Central app state that coordinates all services and the processing pipeline
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: String?

    /// Current state of the main window
    @Published private(set) var mainWindowState: MainWindowState = .permissionRequired

    /// Whether Screen Recording permission is granted
    @Published private(set) var screenRecordingEnabled = false

    /// Whether an API key is configured
    @Published private(set) var apiKeyConfigured = false

    // MARK: - Services

    let hotkeyService = HotkeyService.shared
    let screenCaptureService = ScreenCaptureService.shared
    let clipboardService = ClipboardService.shared
    let llmService = LLMService.shared
    let permissionManager = PermissionManager.shared

    // MARK: - HUD State

    let hudState = HUDState()

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var processingTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        setupHotkeySubscription()
        setupPermissionObserver()
        updateState()
    }

    // MARK: - Setup

    func setup() {
        hotkeyService.register()
        permissionManager.startPolling()
        updateState()
    }

    private func setupHotkeySubscription() {
        hotkeyService.hotkeyTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleHotkeyTrigger()
            }
            .store(in: &cancellables)
    }

    private func setupPermissionObserver() {
        // Observe permission changes
        permissionManager.$screenRecordingEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.screenRecordingEnabled = enabled
                self?.updateMainWindowState()
            }
            .store(in: &cancellables)
    }

    // MARK: - State Management

    /// Update all state values
    func updateState() {
        screenRecordingEnabled = permissionManager.checkPermission()
        apiKeyConfigured = APIConfig.hasAPIKey
        updateMainWindowState()
    }

    /// Refresh API key status (call after saving/clearing key)
    func refreshAPIKeyStatus() {
        apiKeyConfigured = APIConfig.hasAPIKey
        updateMainWindowState()
    }

    private func updateMainWindowState() {
        if !screenRecordingEnabled {
            mainWindowState = .permissionRequired
        } else if !apiKeyConfigured {
            mainWindowState = .apiKeyRequired
        } else {
            mainWindowState = .ready
        }
    }

    // MARK: - Hotkey Handler

    private func handleHotkeyTrigger() {
        // Check if we're ready to process
        guard screenRecordingEnabled else {
            hudState.showError("Screen Recording permission required")
            return
        }

        guard apiKeyConfigured else {
            hudState.showError("API key not configured")
            return
        }

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

        // Stage 1: Gathering context (capturing screenshot)
        hudState.startGathering()

        // Small delay to show gathering stage
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else {
            isProcessing = false
            return
        }

        // Capture screenshot
        guard let context = screenCaptureService.captureWithFallback() else {
            lastError = "Failed to capture screenshot"
            hudState.showError("Couldn't capture screen")
            isProcessing = false
            return
        }

        // Stage 2: Thinking (calling LLM)
        hudState.startThinking()

        do {
            // Call LLM API with screenshot
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

    /// Open Screen Recording settings
    func openScreenRecordingSettings() {
        permissionManager.openScreenRecordingSettings()
    }

    /// Re-check permission status
    func recheckPermission() {
        updateState()
    }
}
