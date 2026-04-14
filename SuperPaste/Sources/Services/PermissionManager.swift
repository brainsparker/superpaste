import AppKit
import CoreGraphics
import Combine

/// Manages Screen Recording and Accessibility permission checking and status.
/// Both permissions are REQUIRED for SuperPaste to function.
@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    // MARK: - Published State

    @Published private(set) var screenRecordingEnabled: Bool = false
    @Published private(set) var accessibilityEnabled: Bool = false

    // MARK: - Private

    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 2.0

    // MARK: - Initialization

    private init() {
        checkPermission()
        checkAccessibilityPermission()
    }

    // MARK: - Public API

    /// Check the current Screen Recording permission status.
    /// Updates the `screenRecordingEnabled` property.
    @discardableResult
    func checkPermission() -> Bool {
        let enabled = CGPreflightScreenCaptureAccess()
        screenRecordingEnabled = enabled
        return enabled
    }

    /// Check the current Accessibility permission status.
    /// Updates the `accessibilityEnabled` property.
    @discardableResult
    func checkAccessibilityPermission() -> Bool {
        let enabled = AXIsProcessTrusted()
        accessibilityEnabled = enabled
        return enabled
    }

    /// Start polling for permission changes.
    /// Useful when the user is expected to enable permission in System Settings.
    func startPolling() {
        stopPolling()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermission()
                self?.checkAccessibilityPermission()
            }
        }
    }

    /// Stop polling for permission changes.
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    /// Request Screen Recording permission and open System Settings.
    func openScreenRecordingSettings() {
        _ = CGRequestScreenCaptureAccess()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Request Accessibility permission (shows system dialog) and open System Settings.
    func openAccessibilitySettings() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    deinit {
        pollingTimer?.invalidate()
    }
}
