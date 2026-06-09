import SwiftUI
import Combine
import CoreGraphics
import AppKit
import ServiceManagement

/// Main window state machine
enum MainWindowState: Equatable {
    case welcome
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

    /// Whether to offer a relaunch after Screen Recording was requested but is not usable yet.
    @Published private(set) var shouldOfferPermissionRelaunch = false

    /// Days remaining in free trial. nil when licensed (no badge shown).
    @Published private(set) var trialDaysRemaining: Int? = nil

    /// Whether a valid license is stored locally (Keychain). Drives UI in Settings.
    @Published private(set) var isLicensed: Bool = LicenseService.shared.hasLocalLicense

    /// Activation status shown in TrialExpiredView / Settings
    @Published var licenseActivationState: LicenseActivationState = .idle

    enum LicenseActivationState: Equatable {
        case idle
        case validating
        case success
        case failure(String)
    }

    /// Whether the user has completed the welcome screen
    @AppStorage("hasSeenWelcome") private(set) var hasSeenWelcome = false

    /// Number of times SuperPaste has been used
    @AppStorage("useCount") private(set) var useCount = 0

    /// Whether SuperPaste should start when the user logs in.
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    /// Tracks the one-time default-on launch-at-login setup after permissions are ready.
    @AppStorage("hasConfiguredLaunchAtLogin") private var hasConfiguredLaunchAtLogin = false

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
        LicenseService.shared.migrateFromUserDefaultsIfNeeded()
        setupHotkeySubscription()
        setupPermissionObserver()
        updateState()
        computeTrialDaysRemaining()
    }

    // MARK: - Setup

    func setup() {
        permissionManager.startPolling()
        updateState()
        refreshHotkeyRegistrationIfPossible()
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
                if enabled {
                    self?.refreshHotkeyRegistrationIfPossible()
                }
                self?.updateMainWindowState()
            }
            .store(in: &cancellables)

        // If CGEvent tap creation fails, AXIsProcessTrusted() lied to us —
        // force back to accessibilityRequired so the user can re-grant it.
        hotkeyService.$accessibilityPermissionDenied
            .receive(on: DispatchQueue.main)
            .filter { $0 }
            .sink { [weak self] _ in
                self?.accessibilityEnabled = false
                self?.updateMainWindowState()
            }
            .store(in: &cancellables)
    }

    // MARK: - State Management

    func updateState() {
        screenRecordingEnabled = permissionManager.checkPermission()
        accessibilityEnabled = permissionManager.checkAccessibilityPermission()
        if screenRecordingEnabled {
            shouldOfferPermissionRelaunch = false
        }
        refreshHotkeyRegistrationIfPossible()
        updateMainWindowState()
    }

    private func refreshHotkeyRegistrationIfPossible() {
        guard accessibilityEnabled, !hotkeyService.isRegistered else {
            return
        }

        hotkeyService.register()
    }

    private func updateMainWindowState() {
        if !hasSeenWelcome {
            mainWindowState = .welcome
        } else if !screenRecordingEnabled {
            mainWindowState = .permissionRequired
        } else if !accessibilityEnabled {
            mainWindowState = .accessibilityRequired
        } else if UserDefaults.standard.bool(forKey: "trialExpiredLocally") {
            mainWindowState = .trialExpired
        } else {
            mainWindowState = .ready
            configureLaunchAtLoginByDefaultIfNeeded()
        }
    }

    private func configureLaunchAtLoginByDefaultIfNeeded() {
        guard !hasConfiguredLaunchAtLogin else { return }
        setLaunchAtLogin(true)
        hasConfiguredLaunchAtLogin = true
    }

    private func computeTrialDaysRemaining() {
        // Keep isLicensed in sync with the underlying Keychain state
        isLicensed = LicenseService.shared.hasLocalLicense

        if isLicensed {
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

        guard let context = screenCaptureService.capture() else {
            lastError = "Failed to capture screenshot"
            hudState.showError("Couldn't capture the active window \u{2014} check Screen Recording permission.")
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

    func activateLicense(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        licenseActivationState = .validating

        Task {
            do {
                try await LicenseService.shared.activate(trimmed)
                UserDefaults.standard.removeObject(forKey: "trialExpiredLocally")
                licenseActivationState = .success
                computeTrialDaysRemaining()
                updateMainWindowState()
            } catch LicenseService.LicenseError.invalidKey {
                licenseActivationState = .failure("License key not recognized.")
            } catch let error as LicenseService.LicenseError {
                licenseActivationState = .failure(error.localizedDescription)
            } catch {
                licenseActivationState = .failure("Couldn't save license: \(error.localizedDescription)")
            }
        }
    }

    func removeLicense() {
        LicenseService.shared.deactivate()
        licenseActivationState = .idle
        computeTrialDaysRemaining()
        updateMainWindowState()
    }

    func openScreenRecordingSettings() {
        shouldOfferPermissionRelaunch = true
        permissionManager.openScreenRecordingSettings()
    }

    func openAccessibilitySettings() {
        permissionManager.openAccessibilitySettings()
    }

    func recheckPermission() {
        updateState()
    }

    func relaunchForPermissions() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundleURL.path]

        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            lastError = "Couldn't relaunch SuperPaste."
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
            launchAtLogin = enabled
        } catch {
            launchAtLogin = service.status == .enabled
            lastError = enabled
                ? "Couldn't enable launch at login."
                : "Couldn't disable launch at login."
            print("Failed to update launch at login: \(error)")
        }
    }
}
