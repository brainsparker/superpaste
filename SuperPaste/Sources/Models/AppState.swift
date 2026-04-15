import SwiftUI
import Combine
import CoreGraphics

/// Main window state machine
enum MainWindowState: Equatable {
    case permissionRequired
    case accessibilityRequired
    case trialExpired
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

    /// Whether Accessibility permission is granted
    @Published private(set) var accessibilityEnabled = false

    /// Days remaining in free trial. nil when licensed (no badge shown).
    @Published private(set) var trialDaysRemaining: Int? = nil

    /// Activation status shown in TrialExpiredView / Settings
    @Published var licenseActivationState: LicenseActivationState = .idle

    enum LicenseActivationState: Equatable {
        case idle
        case validating
        case success
        case failure(String)
    }

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
        computeTrialDaysRemaining()
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
        permissionManager.$screenRecordingEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.screenRecordingEnabled = enabled
                self?.updateMainWindowState()
            }
            .store(in: &cancellables)

        permissionManager.$accessibilityEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.accessibilityEnabled = enabled
                self?.updateMainWindowState()
            }
            .store(in: &cancellables)
    }

    // MARK: - State Management

    func updateState() {
        screenRecordingEnabled = permissionManager.checkPermission()
        accessibilityEnabled = permissionManager.checkAccessibilityPermission()
        updateMainWindowState()
    }

    private func updateMainWindowState() {
        if !screenRecordingEnabled {
            mainWindowState = .permissionRequired
        } else if !accessibilityEnabled {
            mainWindowState = .accessibilityRequired
        } else if UserDefaults.standard.bool(forKey: "trialExpiredLocally") {
            mainWindowState = .trialExpired
        } else {
            mainWindowState = .ready
        }
    }

    private func computeTrialDaysRemaining() {
        // If licensed, no badge needed
        if let key = UserDefaults.standard.string(forKey: "licenseKey"), !key.isEmpty {
            trialDaysRemaining = nil
            return
        }
        // Use local trial start date for display purposes (server enforces actual expiry)
        let trialStartKey = "trialStartDate"
        if UserDefaults.standard.object(forKey: trialStartKey) == nil {
            UserDefaults.standard.set(Date(), forKey: trialStartKey)
        }
        guard let start = UserDefaults.standard.object(forKey: trialStartKey) as? Date else {
            trialDaysRemaining = 7
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = max(0, 7 - Int(elapsed / 86400))
        trialDaysRemaining = remaining
    }

    // MARK: - Hotkey Handler

    private func handleHotkeyTrigger() {
        guard screenRecordingEnabled else {
            hudState.showError("Screen Recording permission required")
            return
        }

        guard accessibilityEnabled else {
            hudState.showError("Accessibility permission required")
            return
        }

        guard mainWindowState != .trialExpired else {
            hudState.showError("Trial ended — enter your license key")
            return
        }

        // If already processing, cancel and restart
        if isProcessing {
            processingTask?.cancel()
            hudState.dismiss()
        }

        processingTask = Task {
            await processPipeline()
        }
    }

    // MARK: - Processing Pipeline

    private func processPipeline() async {
        isProcessing = true
        lastError = nil

        hudState.startGathering()

        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else {
            isProcessing = false
            return
        }

        guard let context = screenCaptureService.captureWithFallback() else {
            lastError = "Failed to capture screenshot"
            hudState.showError("Couldn't capture screen")
            isProcessing = false
            return
        }

        hudState.startThinking()

        do {
            let response = try await llmService.process(context: context)

            guard !Task.isCancelled else {
                isProcessing = false
                return
            }

            clipboardService.write(response)

            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { isProcessing = false; return }
            simulatePaste()

            hudState.showReady()

        } catch LLMService.LLMError.trialExpired {
            guard !Task.isCancelled else { isProcessing = false; return }
            UserDefaults.standard.set(true, forKey: "trialExpiredLocally")
            updateMainWindowState()
            hudState.dismiss()

        } catch LLMService.LLMError.dailyLimitReached {
            guard !Task.isCancelled else { isProcessing = false; return }
            lastError = "Daily limit reached"
            hudState.showError("Daily limit reached. Resets at midnight.")

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

    // MARK: - Auto-Paste

    private func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Manual Actions

    func dismissHUD() {
        processingTask?.cancel()
        hudState.dismiss()
        isProcessing = false
    }

    func activateLicense(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        licenseActivationState = .validating

        Task {
            do {
                let valid = try await llmService.validateLicense(trimmed)
                if valid {
                    UserDefaults.standard.set(trimmed, forKey: "licenseKey")
                    UserDefaults.standard.removeObject(forKey: "trialExpiredLocally")
                    licenseActivationState = .success
                    computeTrialDaysRemaining()
                    updateMainWindowState()
                } else {
                    licenseActivationState = .failure("License key not recognized.")
                }
            } catch {
                licenseActivationState = .failure("Couldn't connect. Check your internet connection.")
            }
        }
    }

    func removeLicense() {
        UserDefaults.standard.removeObject(forKey: "licenseKey")
        licenseActivationState = .idle
        computeTrialDaysRemaining()
        updateMainWindowState()
    }

    func openScreenRecordingSettings() {
        permissionManager.openScreenRecordingSettings()
    }

    func openAccessibilitySettings() {
        permissionManager.openAccessibilitySettings()
    }

    func recheckPermission() {
        updateState()
    }
}
