import AppKit
import CoreGraphics

enum PermissionStatusReporter {
    struct Status {
        let screenRecordingEnabled: Bool
        let accessibilityEnabled: Bool
        let hotkeyEventTapAvailable: Bool

        var isReady: Bool {
            screenRecordingEnabled && accessibilityEnabled && hotkeyEventTapAvailable
        }
    }

    static func currentStatus() -> Status {
        let accessibilityEnabled = AXIsProcessTrusted()

        return Status(
            screenRecordingEnabled: screenRecordingEnabled(),
            accessibilityEnabled: accessibilityEnabled,
            hotkeyEventTapAvailable: hotkeyEventTapAvailable()
        )
    }

    static func printStatus() -> Int32 {
        let status = currentStatus()
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"

        print("SuperPaste permission status")
        print("----------------------------------------")
        print("Bundle id:         \(bundleID)")
        print("Screen Recording:  \(status.screenRecordingEnabled ? "granted" : "missing")")
        print("Accessibility:     \(status.accessibilityEnabled ? "granted" : "missing")")
        print("Hotkey event tap:  \(status.hotkeyEventTapAvailable ? "available" : "unavailable")")
        print("Ready:             \(status.isReady ? "yes" : "no")")

        if !status.isReady {
            print("")
            print("Open SuperPaste and follow the permission setup screen.")
            print("If System Settings already shows Screen Recording enabled, relaunch SuperPaste once.")
        }

        return status.isReady ? 0 : 1
    }

    /// Matches PermissionManager.checkPermission() exactly — CGPreflight
    /// first, then the capability probe (reading other apps' window names).
    private static func screenRecordingEnabled() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        let currentPID = getpid()

        return windowList.contains { window in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID != currentPID,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let windowName = window[kCGWindowName as String] as? String
            else {
                return false
            }

            return !windowName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Creates a head-insert, consuming event tap — the exact same parameters
    /// the real hotkey uses. A listen-only or tail-append tap can succeed when
    /// Accessibility isn't sufficient for the real hotkey, producing false
    /// "ready" reports.
    private static func hotkeyEventTapAvailable() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in
                // Don't consume the event during probe — we're only checking
                // if the tap CAN be created, not actually intercepting keys.
                Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )

        guard let tap else {
            return false
        }

        CFMachPortInvalidate(tap)
        return true
    }
}