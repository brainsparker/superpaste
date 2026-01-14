import AppKit
import CoreGraphics
import Combine

/// Manages Screen Recording permission checking and status.
/// Screen Recording permission is REQUIRED for SuperPaste to function.
@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    // MARK: - Published State

    @Published private(set) var screenRecordingEnabled: Bool = false

    // MARK: - Private

    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 2.0

    // MARK: - Initialization

    private init() {
        checkPermission()
    }

    // MARK: - Public API

    /// Check the current Screen Recording permission status.
    /// Updates the `screenRecordingEnabled` property.
    @discardableResult
    func checkPermission() -> Bool {
        let enabled = checkScreenRecordingPermission()
        screenRecordingEnabled = enabled
        return enabled
    }

    /// Start polling for permission changes.
    /// Useful when the user is expected to enable permission in System Settings.
    func startPolling() {
        stopPolling()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermission()
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
        // First, request permission - this will show the system dialog if not yet prompted
        // After the first prompt, this just returns the current status
        _ = CGRequestScreenCaptureAccess()

        // Also open System Settings so user can toggle the permission
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    /// Check if Screen Recording permission is granted.
    /// Uses CGPreflightScreenCaptureAccess on macOS 10.15+
    private func checkScreenRecordingPermission() -> Bool {
        // Use the modern API (macOS 10.15+)
        return CGPreflightScreenCaptureAccess()
    }

    deinit {
        pollingTimer?.invalidate()
    }
}
