import SwiftUI
import Combine
import CoreGraphics

/// Main window state machine
enum MainWindowState: Equatable {
    case welcome
    case permissionRequired
    case accessibilityRequired
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

    /// Whether the user has completed the welcome screen
    @AppStorage("hasSeenWelcome") private(set) var hasSeenWelcome = false

    /// Number of times SuperPaste has been used
    @AppStorage("useCount") private(set) var useCount = 0

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
        if !hasSeenWelcome {
            mainWindowState = .welcome
        } else if !screenRecordingEnabled {
            mainWindowState = .permissionRequired
        } else if !accessibilityEnabled {
            mainWindowState = .accessibilityRequired
        } else {
            mainWindowState = .ready
        }
    }

    /// Mark the welcome screen as seen and advance to next state
    func dismissWelcome() {
        hasSeenWelcome = true
        updateMainWindowState()
    }

    // MARK: - Hotkey Handler

    private func handleHotkeyTrigger() {
        guard screenRecordingEnabled else {
            hudState.showError("Screen Recording permission required \u{2014} open System Settings to enable.")
            return
        }

        guard accessibilityEnabled else {
            hudState.showError("Accessibility permission required \u{2014} open System Settings to enable.")
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
            hudState.showError("Couldn't capture your screen \u{2014} check Screen Recording permission.")
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

            useCount += 1
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
            hudState.showError(error.localizedDescription)
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
