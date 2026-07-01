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

    /// Last generated response, kept so the user can recover it (menu bar →
    /// Copy Last Response) after the clipboard is restored or a paste misfires.
    @Published private(set) var lastResponse: String?

    /// When paused, the hotkey is unregistered and the keystroke belongs to
    /// other apps again.
    @Published private(set) var isPaused = false

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

    /// Whether a user-supplied Anthropic API key is active (bring-your-own-key mode).
    @Published private(set) var usingOwnAPIKey: Bool = UserAPIKey.current != nil

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
    /// Off by default — enabling login items silently right after two invasive
    /// permission grants is exactly the wrong trust move; the user opts in.
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    // MARK: - Services

    let hotkeyService = HotkeyService.shared
    let screenCaptureService = ScreenCaptureService.shared
    let clipboardService = ClipboardService.shared
    let llmService = LLMService.shared
    let permissionManager = PermissionManager.shared
    let updateChecker = UpdateChecker.shared

    // MARK: - HUD State

    let hudState = HUDState()

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var processingTask: Task<Void, Never>?

    /// Monotonic pipeline token. Every trigger bumps it; a pipeline only
    /// mutates shared state (isProcessing, HUD, paste) while its own token is
    /// still current. Without this, a cancelled pipeline's teardown races the
    /// next one and two pastes can fire.
    private var pipelineGeneration = 0

    // MARK: - Initialization

    init() {
        LicenseService.shared.migrateFromUserDefaultsIfNeeded()
        setupHotkeySubscription()
        setupPermissionObserver()
        updateState()
        computeTrialDaysRemaining()

        hudState.onCancel = { [weak self] in
            self?.cancelProcessing()
        }
        hotkeyService.escapeInterceptor = { [weak self] in
            self?.isProcessing ?? false
        }
    }

    // MARK: - Setup

    func setup() {
        permissionManager.startPolling()
        updateState()
        refreshHotkeyRegistrationIfPossible()
        updateChecker.checkIfStale()
    }

    private func setupHotkeySubscription() {
        hotkeyService.hotkeyTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleHotkeyTrigger()
            }
            .store(in: &cancellables)

        hotkeyService.escapePressed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.cancelProcessing()
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
                guard let self else { return }
                let wasEnabled = self.accessibilityEnabled
                self.accessibilityEnabled = enabled
                if enabled && !wasEnabled && self.hotkeyService.isRegistered {
                    // Revoke + re-grant leaves the old tap dead while
                    // isRegistered stays true — rebuild it.
                    self.hotkeyService.reRegister()
                } else if enabled {
                    self.refreshHotkeyRegistrationIfPossible()
                }
                self.updateMainWindowState()
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
        guard accessibilityEnabled, !isPaused, !hotkeyService.isRegistered else {
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
        } else if UserDefaults.standard.bool(forKey: "trialExpiredLocally") && !usingOwnAPIKey {
            mainWindowState = .trialExpired
        } else {
            mainWindowState = .ready
        }
    }

    private func computeTrialDaysRemaining() {
        // Keep isLicensed in sync with the underlying Keychain state
        isLicensed = LicenseService.shared.hasLocalLicense

        if isLicensed || usingOwnAPIKey {
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

    // MARK: - Pause

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            if isProcessing { cancelProcessing() }
            hotkeyService.unregister()
        } else {
            refreshHotkeyRegistrationIfPossible()
        }
    }

    // MARK: - Hotkey Handler

    private func handleHotkeyTrigger() {
        guard !isPaused else { return }

        guard screenRecordingEnabled else {
            hudState.showError("Screen Recording permission required \u{2014} open System Settings to enable.")
            return
        }

        guard accessibilityEnabled else {
            hudState.showError("Accessibility permission required \u{2014} open System Settings to enable.")
            return
        }

        // Keep the trial badge honest even if the app has been running for days.
        computeTrialDaysRemaining()

        guard mainWindowState != .trialExpired else {
            hudState.showError("Trial ended — subscribe or add your own API key in Settings")
            return
        }

        // Second press = cancel. Restarting on a fat-fingered double press
        // would double the wait AND the request cost.
        if isProcessing {
            cancelProcessing()
            return
        }

        pipelineGeneration += 1
        let generation = pipelineGeneration
        processingTask = Task {
            await processPipeline(generation: generation)
        }
    }

    /// Cancel the in-flight pipeline (Esc, HUD ✕, second hotkey press, pause).
    func cancelProcessing() {
        pipelineGeneration += 1
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        hudState.dismiss()
    }

    // MARK: - Processing Pipeline

    private func processPipeline(generation: Int) async {
        isProcessing = true
        lastError = nil

        hudState.startGathering()

        try? await Task.sleep(for: .milliseconds(100))
        guard isCurrent(generation) else { return }

        // Never capture password managers or anything focused on a secure
        // input field — the privacy promise has to hold at the worst moment.
        let frontApp = NSWorkspace.shared.frontmostApplication
        switch SensitiveContextGuard.check(
            bundleIdentifier: frontApp?.bundleIdentifier,
            appName: frontApp?.localizedName
        ) {
        case .secureInputActive:
            failPipeline(generation, message: "A password field is focused \u{2014} SuperPaste won't capture that.")
            return
        case .blockedApp(let name):
            failPipeline(generation, message: "SuperPaste is disabled in \(name) to protect your secrets.")
            return
        case .allowed:
            break
        }

        // The in-app practice moment needs to capture SuperPaste's own window;
        // everywhere else our own windows are excluded from capture.
        let allowOwnWindow = !UserDefaults.standard.bool(forKey: "hasTriedOnce")
        let context: ScreenCaptureService.CapturedContext
        do {
            context = try await screenCaptureService.capture(allowOwnWindow: allowOwnWindow)
        } catch let error as ScreenCaptureService.CaptureError {
            failPipeline(generation, message: Self.message(for: error))
            return
        } catch {
            failPipeline(generation, message: "Couldn't capture the active window \u{2014} try again.")
            return
        }

        guard isCurrent(generation) else { return }
        hudState.startThinking()

        do {
            let response = try await llmService.process(context: context)
            guard isCurrent(generation) else { return }

            lastResponse = response

            // If the user switched apps during the round trip, a synthetic ⌘V
            // would paste AI text into whatever is focused NOW. Don't.
            let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if let capturedPID = context.frontmostPID, currentPID != capturedPID {
                clipboardService.write(response)
                useCount += 1
                UserDefaults.standard.set(true, forKey: "hasTriedOnce")
                hudState.showError("Focus changed \u{2014} response copied. Press \u{2318}V to paste it.")
                finishPipeline(generation)
                return
            }

            let previousClipboard = clipboardService.snapshotItems()
            clipboardService.write(response)
            let ourChangeCount = clipboardService.changeCount

            try? await Task.sleep(for: .milliseconds(50))
            guard isCurrent(generation) else {
                // Cancelled between the clipboard write and the paste: nothing
                // was pasted, so hand the clipboard straight back.
                if clipboardService.changeCount == ourChangeCount {
                    clipboardService.restore(previousClipboard)
                }
                return
            }
            simulatePaste()

            useCount += 1
            // Ends the onboarding practice moment and, with it, permission to
            // capture SuperPaste's own window.
            UserDefaults.standard.set(true, forKey: "hasTriedOnce")
            hudState.showReady()

            // Give the target app time to service the paste, then hand the
            // clipboard back — a paste tool must not eat what the user copied.
            restoreClipboardLater(previousClipboard, ifChangeCountStillEquals: ourChangeCount)

        } catch LLMService.LLMError.trialExpired {
            guard isCurrent(generation) else { return }
            UserDefaults.standard.set(true, forKey: "trialExpiredLocally")
            updateMainWindowState()
            hudState.showError("Trial ended \u{2014} subscribe or add your own API key in Settings")

        } catch let error as LLMService.LLMError {
            guard isCurrent(generation) else { return }
            lastError = error.errorDescription
            hudState.showError(error.userFriendlyMessage)

        } catch {
            guard isCurrent(generation) else { return }
            lastError = error.localizedDescription
            hudState.showError(error.localizedDescription)
        }

        finishPipeline(generation)
    }

    /// True while this pipeline run is still the active one.
    private func isCurrent(_ generation: Int) -> Bool {
        if generation != pipelineGeneration || Task.isCancelled {
            // A newer run owns the shared state now; don't touch it.
            return false
        }
        return true
    }

    private func failPipeline(_ generation: Int, message: String) {
        guard isCurrent(generation) else { return }
        lastError = message
        hudState.showError(message)
        finishPipeline(generation)
    }

    private func finishPipeline(_ generation: Int) {
        guard generation == pipelineGeneration else { return }
        isProcessing = false
    }

    private func restoreClipboardLater(_ previous: [NSPasteboardItem], ifChangeCountStillEquals changeCount: Int) {
        guard !previous.isEmpty else { return }
        Task { [weak self] in
            // Generous delay: a busy app may service the synthetic ⌘V well
            // after it was posted, and pasting the OLD clipboard into the
            // reply field would be far worse than a late restore.
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self else { return }
            // Only restore if nothing else (including the user) wrote to the
            // clipboard since our paste.
            if self.clipboardService.changeCount == changeCount {
                self.clipboardService.restore(previous)
            }
        }
    }

    private static func message(for error: ScreenCaptureService.CaptureError) -> String {
        switch error {
        case .ownWindowOnly:
            return "Click into the app you want to paste into, then press \(HotkeyPreset.current.shortName)."
        case .noWindow:
            return "Couldn't find a window to capture \u{2014} click into the app you want to paste into."
        case .blackFrame:
            return "This window captures as a black frame (protected content) \u{2014} try a different window."
        case .captureFailed:
            return "Couldn't capture the active window \u{2014} check Screen Recording permission."
        }
    }

    // MARK: - Auto-Paste

    private func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        // Resolve the key that actually types "v" on the current layout —
        // key code 9 is only "v" on ANSI QWERTY.
        let vKey = KeyboardLayout.vKeyCode
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Manual Actions

    func dismissHUD() {
        cancelProcessing()
    }

    func copyLastResponse() {
        guard let lastResponse else { return }
        clipboardService.write(lastResponse)
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

    // MARK: - Bring-your-own-key

    func setUserAPIKey(_ key: String) {
        do {
            try UserAPIKey.set(key)
            usingOwnAPIKey = UserAPIKey.current != nil
            if usingOwnAPIKey {
                UserDefaults.standard.removeObject(forKey: "trialExpiredLocally")
            }
            computeTrialDaysRemaining()
            updateMainWindowState()
        } catch {
            lastError = "Couldn't save the API key."
        }
    }

    func clearUserAPIKey() {
        UserAPIKey.clear()
        usingOwnAPIKey = false
        computeTrialDaysRemaining()
        updateMainWindowState()
    }

    // MARK: - Permissions helpers

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
