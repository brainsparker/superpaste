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

    /// Whether to offer a relaunch after Screen Recording was requested but the capability
    /// probe still fails. Derived from PermissionManager's heuristic.
    @Published private(set) var shouldOfferPermissionRelaunch = false

    /// Days remaining in free trial. nil when licensed or using own key (no badge shown).
    @Published private(set) var trialDaysRemaining: Int? = nil

    /// Whether a valid license is stored locally (Keychain). Drives UI in Settings.
    @Published private(set) var isLicensed: Bool = LicenseService.shared.hasLocalLicense

    /// Whether the selected provider serves pastes outside the hosted backend:
    /// a bring-your-own key, or a keyless local server (Ollama, LM Studio).
    /// Drives trial enforcement, so it must track the selected provider rather
    /// than "some key exists somewhere".
    @Published private(set) var usingOwnAPIKey: Bool = LLMService.currentConfig().isOwnProviderReady

    /// Which provider is currently configured.
    @Published private(set) var providerConfig: LLMProviderConfig = LLMService.currentConfig()

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
    let captureExclusions = CaptureExclusions()
    @Published private(set) var hasCompetingInstance = false
    @Published private(set) var hotkeyUnavailable = false
    @Published private(set) var captureApp: NSRunningApplication?

    // MARK: - HUD State

    let hudState = HUDState()
    let trialAccount = TrialAccountService.shared

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var processingTask: Task<Void, Never>?
    private var clipboardRestoreTask: Task<Void, Never>?
    private let clipboardRestoration = ClipboardRestoration<[NSPasteboardItem]>()

    /// Monotonic pipeline token. Every trigger bumps it; a pipeline only
    /// mutates shared state (isProcessing, HUD, paste) while its own token is
    /// still current. Without this, a cancelled pipeline's teardown races the
    /// next one and two pastes can fire.
    private var pipelineToken = PipelineToken()
    @Published private(set) var practiceProgress: PracticeProgress = .idle
    var practiceFieldFocused = false
    private var expectedPracticeReply: String?
    private var practiceGeneration: Int?
    private var pipelineAccountGeneration: Int?

    // MARK: - Initialization

    init() {
        LicenseService.shared.migrateFromUserDefaultsIfNeeded()
        setupHotkeySubscription()
        setupPermissionObserver()
        setupWorkspaceObservers()
        trialAccount.$isSigningIn.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] signingIn in
            guard let self, signingIn, self.isProcessing, self.pipelineAccountGeneration != nil else { return }
            self.cancelProcessing()
        }.store(in: &cancellables)
        trialAccount.$revision.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            if !self.trialAccount.hasSession && self.providerConfig.provider == .superpaste && !self.isLicensed && self.isProcessing { self.cancelProcessing() }
            self.computeTrialDaysRemaining()
            self.updateMainWindowState()
        }.store(in: &cancellables)
        refreshCompetingInstances()
        updateState()
        computeTrialDaysRemaining()

        hudState.onCancel = { [weak self] in
            self?.cancelProcessing()
        }
        hudState.onRetry = { [weak self] in
            self?.retryLastRequest()
        }
        hudState.onCopyResponse = { [weak self] in
            self?.copyLastResponse()
        }
        hudState.onScreenPermission = { [weak self] in self?.openScreenRecordingSettings() }
        hudState.onAccessibilityPermission = { [weak self] in self?.openAccessibilitySettings() }
        hotkeyService.escapeInterceptor = { [weak self] in
            self?.isProcessing ?? false
        }
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
                if !enabled, self?.isProcessing == true { self?.cancelProcessing() }
                self?.updateMainWindowState()
            }
            .store(in: &cancellables)

        permissionManager.$mayNeedRelaunch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.shouldOfferPermissionRelaunch = value
            }
            .store(in: &cancellables)

        permissionManager.$accessibilityEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                let wasEnabled = self.accessibilityEnabled
                self.accessibilityEnabled = enabled
                if !enabled {
                    self.hotkeyService.unregister()
                    if self.isProcessing { self.cancelProcessing() }
                }
                if enabled && !wasEnabled && self.hotkeyService.isRegistered {
                    self.hotkeyService.reRegister()
                } else if enabled {
                    self.refreshHotkeyRegistrationIfPossible()
                }
                self.updateMainWindowState()
            }
            .store(in: &cancellables)

        hotkeyService.$accessibilityPermissionDenied
            .receive(on: DispatchQueue.main)
            .sink { [weak self] denied in self?.hotkeyUnavailable = denied }
            .store(in: &cancellables)

    }

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification] {
            center.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.refreshCompetingInstances()
                    self?.updateState()
                }
                .store(in: &cancellables)
        }
        center.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.cancelProcessing() }
            .store(in: &cancellables)

        // Screen Recording only takes effect after a restart, so mid-setup the
        // user quits — via macOS's "Quit & Reopen" prompt or ⌘Q — and then has
        // to hunt for the app. Bring it back so setup picks up where it left off.
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                guard let self, self.shouldOfferPermissionRelaunch, !self.screenRecordingEnabled else { return }
                AppRelauncher.reopenAfterExit()
            }
            .store(in: &cancellables)
    }

    private func refreshCompetingInstances() {
        let apps = NSWorkspace.shared.runningApplications
        let family = ["com.superpaste.app", "com.superpaste.app.dev"]
        hasCompetingInstance = apps.contains {
            $0.processIdentifier != getpid() && family.contains($0.bundleIdentifier ?? "")
        }
        if hasCompetingInstance {
            hotkeyService.unregister()
            if isProcessing { cancelProcessing() }
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           !family.contains(front.bundleIdentifier ?? "") { captureApp = front }
    }

    // MARK: - State Management

    func updateState() {
        screenRecordingEnabled = permissionManager.checkPermission()
        accessibilityEnabled = permissionManager.checkAccessibilityPermission()
        shouldOfferPermissionRelaunch = permissionManager.mayNeedRelaunch
        refreshHotkeyRegistrationIfPossible()
        updateMainWindowState()
    }

    private func refreshHotkeyRegistrationIfPossible() {
        guard accessibilityEnabled, !hasCompetingInstance, !isPaused, !hotkeyService.isRegistered else {
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
        } else if trialAccount.trialExpired && !usingOwnAPIKey && !isLicensed {
            mainWindowState = .trialExpired
        } else {
            mainWindowState = .ready
        }
    }

    private func computeTrialDaysRemaining() {
        isLicensed = LicenseService.shared.hasLocalLicense
        usingOwnAPIKey = providerConfig.isOwnProviderReady

        if isLicensed || usingOwnAPIKey {
            trialDaysRemaining = nil
            return
        }
        trialDaysRemaining = trialAccount.daysRemaining
    }

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
            hudState.showError(.init(code: .screenPermission, message: "Screen Recording permission required.", recovery: .screenPermission))
            return
        }

        guard accessibilityEnabled else {
            hudState.showError(.init(code: .accessibilityPermission, message: "Accessibility permission required.", recovery: .accessibilityPermission))
            return
        }

        computeTrialDaysRemaining()
        if providerConfig.provider != .superpaste && !providerConfig.isOwnProviderReady {
            hudState.showError(.provider(.providerNotConfigured))
            return
        }

        if providerConfig.provider == .superpaste && !isLicensed && !trialAccount.hasSession {
            hudState.showError(.provider(.trialSignInRequired))
            return
        }

        guard mainWindowState != .trialExpired else {
            hudState.showError(.provider(.trialExpired))
            return
        }

        if isProcessing {
            cancelProcessing()
            return
        }

        clipboardRestoreTask?.cancel()
        guard clipboardRestoration.settle(changeCount: clipboardService.changeCount, restore: clipboardService.restore, currentOwnedCount: { self.clipboardService.ownedChangeCount }) else {
            hudState.showError(.init(code: .pasteUnavailable, message: "Couldn't restore your clipboard. Try again.", recovery: .retry))
            return
        }
        guard let destination = PasteDestination.current() else {
            hudState.showError(.init(code: .destinationChanged, message: "Click into an editable text field, then try again.", recovery: nil))
            return
        }
        let generation = pipelineToken.advance()
        pipelineAccountGeneration = providerConfig.provider == .superpaste && !isLicensed ? trialAccount.generation : nil
        isProcessing = true
        let clipboardCount = clipboardService.changeCount
        let isPractice = practiceFieldFocused && NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
        if isPractice {
            practiceProgress = .hotkeyReceived
            expectedPracticeReply = nil
            practiceGeneration = generation
        }
        processingTask = Task {
            await processPipeline(generation: generation, destination: destination, clipboardCount: clipboardCount, isPractice: isPractice)
        }
    }

    /// Cancel the in-flight pipeline (Esc, HUD ✕, second hotkey press, pause).
    func cancelProcessing() {
        _ = pipelineToken.advance()
        expectedPracticeReply = nil
        practiceGeneration = nil
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        hudState.dismiss()
    }

    /// Show the status bubble without taking a screenshot or making an AI request.
    func previewHUD() {
        guard !isProcessing else { return }
        hudState.preview()
    }

    // MARK: - Processing Pipeline

    private func processPipeline(generation: Int, destination: PasteDestination, clipboardCount: Int, isPractice: Bool) async {
        guard isCurrent(generation) else { return }
        isProcessing = true
        lastError = nil
        if providerConfig.provider == .superpaste && !isLicensed {
            hudState.startCheckingAccount()
            do { _ = try await trialAccount.authorizationHeader() }
            catch {
                guard isCurrent(generation) else { return }
                hudState.showError(.provider(.trialSignInRequired))
                finishPipeline(generation)
                return
            }
            guard isCurrent(generation) else { return }
        }

        // Magic Copy: a Smart Share campaign link on the clipboard means the
        // user wants a post written for wherever they are, not a reading of the
        // window. Checked first because it needs no screenshot at all.
        if let campaignLink = SmartShareLink.inClipboard(clipboardService) {
            await processMagicCopy(generation: generation, link: campaignLink, destination: destination, clipboardCount: clipboardCount)
            return
        }

        hudState.startGathering()

        try? await Task.sleep(for: .milliseconds(100))
        guard isCurrent(generation) else { return }

        let frontApp = NSWorkspace.shared.frontmostApplication
        if let id = frontApp?.bundleIdentifier, captureExclusions.contains(id) {
            failPipeline(generation, message: "Capture is disabled for this app. Manage exclusions in Settings.")
            return
        }
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

        let allowOwnWindow = isPractice
        let context: ScreenCaptureService.CapturedContext
        do {
            context = try await screenCaptureService.capture(destination: destination, allowOwnWindow: allowOwnWindow)
        } catch let error as ScreenCaptureService.CaptureError {
            failPipeline(generation, message: Self.message(for: error))
            return
        } catch {
            failPipeline(generation, message: "Couldn't capture the active window \u{2014} try again.")
            return
        }

        guard isCurrent(generation) else { return }
        guard destination.isStillFocused(), context.frontmostPID == destination.pid,
              permissionManager.checkPermission(), captureAllowed(context.bundleIdentifier, context.appName) else {
            failPipeline(generation, message: "The capture destination changed. Try again.")
            return
        }
        if isPractice { practiceProgress = .captured }
        hudState.startThinking()

        do {
            let response = try await llmService.process(context: context)
            guard isCurrent(generation) else { return }

            lastResponse = response

            if isPractice { practiceProgress = .generated }
            await pasteResponse(response, generation: generation, destination: destination,
                                clipboardCount: clipboardCount, isPractice: isPractice)

        } catch LLMService.LLMError.trialExpired {
            guard isCurrent(generation) else { return }
            updateMainWindowState()
            hudState.showError(.provider(.trialExpired))

        } catch let error as LLMService.LLMError {
            guard isCurrent(generation) else { return }
            lastError = error.errorDescription
            hudState.showError(.provider(error))

        } catch {
            guard isCurrent(generation) else { return }
            lastError = error.localizedDescription
            hudState.showError(.init(code: .unknown, message: "Couldn’t complete the request. Try again.", recovery: .retry))
        }

        finishPipeline(generation)
    }

    // MARK: - Magic Copy

    /// Write a share post for the campaign link on the clipboard and paste it.
    ///
    /// Takes no screenshot: the campaign supplies the content and the frontmost
    /// app supplies the destination, so there is nothing to read off the screen.
    /// That makes it faster than a normal paste and means nothing about the
    /// user's screen leaves the machine.
    private func processMagicCopy(generation: Int, link: String, destination: PasteDestination, clipboardCount: Int) async {
        guard isCurrent(generation) else { return }
        guard destination.isStillFocused() else {
            failPipeline(generation, message: "The destination changed. Try again.")
            return
        }
        // Still refuse secure input. Nothing is captured here, but pasting into
        // a focused password field would be its own kind of wrong.
        let frontApp = NSWorkspace.shared.frontmostApplication
        if case .secureInputActive = SensitiveContextGuard.check(
            bundleIdentifier: frontApp?.bundleIdentifier,
            appName: frontApp?.localizedName
        ) {
            failPipeline(generation, message: "A password field is focused \u{2014} SuperPaste won't paste there.")
            return
        }

        let target = screenCaptureService.frontmostWindowTarget(destination: destination)
        hudState.startWritingShare()

        do {
            let response = try await llmService.processShareCampaign(link: link, target: target)
            guard isCurrent(generation) else { return }

            lastResponse = response

            await pasteResponse(response, generation: generation, destination: destination,
                                clipboardCount: clipboardCount, isPractice: false)

        } catch LLMService.LLMError.trialExpired {
            guard isCurrent(generation) else { return }
            updateMainWindowState()
            hudState.showError(.provider(LLMService.LLMError.trialExpired))

        } catch let error as LLMService.LLMError {
            guard isCurrent(generation) else { return }
            lastError = error.errorDescription
            hudState.showError(.provider(error))

        } catch {
            guard isCurrent(generation) else { return }
            lastError = error.localizedDescription
            hudState.showError(.init(code: .unknown, message: "Couldn\u{2019}t complete the request. Try again.", recovery: .retry))
        }

        finishPipeline(generation)
    }

    /// True while this pipeline run is still the active one.
    private func isCurrent(_ generation: Int) -> Bool {
        pipelineToken.accepts(generation) && !Task.isCancelled
            && (pipelineAccountGeneration == nil || pipelineAccountGeneration == trialAccount.generation)
    }

    private func failPipeline(_ generation: Int, message: String) {
        guard isCurrent(generation) else { return }
        lastError = message
        hudState.showError(.init(code: .capture, message: message, recovery: nil))
        finishPipeline(generation)
    }

    private func finishPipeline(_ generation: Int) {
        guard pipelineToken.accepts(generation) else { return }
        isProcessing = false
    }

    private func captureAllowed(_ bundleID: String?, _ name: String?) -> Bool {
        if let bundleID, captureExclusions.contains(bundleID) { return false }
        if case .allowed = SensitiveContextGuard.check(bundleIdentifier: bundleID, appName: name) { return true }
        return false
    }

    private func pasteResponse(_ response: String, generation: Int, destination: PasteDestination,
                               clipboardCount: Int, isPractice: Bool) async {
        guard isCurrent(generation) else { return }
        let previous = clipboardService.snapshotItems()
        var expectedCount = clipboardCount
        let outcome = await PasteTransaction.run(
            isCurrent: { self.isCurrent(generation) },
            destinationMatches: {
                destination.isStillFocused() && self.permissionManager.checkAccessibilityPermission()
                    && self.captureAllowed(NSRunningApplication(processIdentifier: destination.pid)?.bundleIdentifier, nil)
            },
            clipboardMatches: { self.clipboardService.changeCount == expectedCount },
            prepareClipboard: {
                let written = self.clipboardService.write(response)
                expectedCount = self.clipboardService.ownedChangeCount ?? -1
                if expectedCount != -1 {
                    self.clipboardRestoration.remember(previous, changeCount: expectedCount)
                    self.scheduleClipboardRestoration()
                }
                return written
            },
            restoreClipboard: {
                if !self.clipboardRestoration.settle(changeCount: self.clipboardService.changeCount,
                    restore: self.clipboardService.restore, currentOwnedCount: { self.clipboardService.ownedChangeCount }) {
                    self.lastError = "Couldn't restore your clipboard."
                }
            },
            paste: {
                if isPractice { self.expectedPracticeReply = response }
                return self.simulatePaste()
            }
        )
        guard isCurrent(generation) else { return }
        switch outcome {
        case .pasted:
            useCount += 1
            if !isPractice { UserDefaults.standard.set(true, forKey: "hasTriedOnce") }
            hudState.showReady()
            scheduleClipboardRestoration()
        case .destinationChanged:
            hudState.showError(.destinationChanged)
        case .clipboardChanged:
            hudState.showError(.init(code: .clipboardChanged, message: "Your clipboard changed. Your response is ready to copy.", recovery: .copyResponse))
        case .clipboardUnavailable, .pasteUnavailable:
            hudState.showError(.init(code: .pasteUnavailable, message: "Couldn't prepare the paste. Your response is ready to copy.", recovery: .copyResponse))
        case .cancelled: break
        }
        if outcome != .pasted { expectedPracticeReply = nil }
    }

    private func scheduleClipboardRestoration() {
        clipboardRestoreTask?.cancel()
        clipboardRestoreTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            if !self.clipboardRestoration.settle(changeCount: self.clipboardService.changeCount,
                restore: self.clipboardService.restore, currentOwnedCount: { self.clipboardService.ownedChangeCount }) {
                self.lastError = "Couldn't restore your clipboard."
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

    private func simulatePaste() -> Bool {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey = KeyboardLayout.vKeyCode
        guard let vDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) else { return false }
        vDown.flags = .maskCommand
        vUp.flags   = .maskCommand
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        return true
    }

    func observePracticeReply(_ text: String) {
        guard let expectedPracticeReply, let generation = practiceGeneration,
              pipelineToken.accepts(generation), practiceFieldFocused,
              text.contains(expectedPracticeReply) else { return }
        practiceProgress = .inserted
        self.expectedPracticeReply = nil
    }

    // MARK: - Manual Actions

    func dismissHUD() {
        cancelProcessing()
    }

    func copyLastResponse() {
        guard let lastResponse else { return }
        clipboardService.write(lastResponse)
    }

    func retryLastRequest() {
        guard !isProcessing else { return }
        handleHotkeyTrigger()
    }

    // MARK: - License

    func activateLicense(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        licenseActivationState = .validating

        Task {
            do {
                try await LicenseService.shared.activate(trimmed)
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

    // MARK: - Provider configuration

    func setProviderConfig(_ config: LLMProviderConfig) {
        if isProcessing { cancelProcessing() }
        providerConfig = config
        LLMService.saveConfig(config)
        computeTrialDaysRemaining()
        updateMainWindowState()
    }

    func setAPIKey(_ key: String, for provider: LLMProviderID) {
        do {
            try UserCredentialStore.set(apiKey: key, for: provider)
            computeTrialDaysRemaining()
            updateMainWindowState()
        } catch {
            lastError = "Couldn't save the API key."
        }
    }

    func clearAPIKey(for provider: LLMProviderID) {
        UserCredentialStore.clear(for: provider)
        computeTrialDaysRemaining()
        updateMainWindowState()
    }

    // MARK: - Permissions helpers

    func openScreenRecordingSettings() {
        permissionManager.openScreenRecordingSettings()
    }

    func openAccessibilitySettings() {
        permissionManager.openAccessibilitySettings()
    }

    /// Immediate re-check — called when the user clicks "Check Again" so they
    /// don't have to wait for the next poll cycle.
    func recheckPermission() {
        updateState()
    }

    func relaunchForPermissions() {
        // willTerminate schedules the reopen while setup is pending; schedule
        // it here too so the button works even after that state clears.
        guard AppRelauncher.reopenAfterExit() else {
            lastError = "Couldn't relaunch SuperPaste."
            return
        }
        shouldOfferPermissionRelaunch = false
        NSApp.terminate(nil)
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
        }
    }
}