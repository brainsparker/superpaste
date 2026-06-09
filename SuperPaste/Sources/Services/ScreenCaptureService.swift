import AppKit
import CoreGraphics

/// Service for capturing screenshots of the active window.
/// Requires Screen Recording permission.
final class ScreenCaptureService {
    static let shared = ScreenCaptureService()

    private init() {}

    // MARK: - Types

    /// Captured context containing screenshot and metadata.
    struct CapturedContext {
        let screenshot: CGImage
        let appName: String?
        let windowTitle: String?

        /// Convert screenshot to base64-encoded PNG for API transmission.
        func base64EncodedPNG() -> String? {
            // Create NSBitmapImageRep from CGImage
            let bitmapRep = NSBitmapImageRep(cgImage: screenshot)

            // Convert to PNG data
            guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                return nil
            }

            // Base64 encode
            return pngData.base64EncodedString()
        }

        /// Get the image data as PNG.
        func pngData() -> Data? {
            let bitmapRep = NSBitmapImageRep(cgImage: screenshot)
            return bitmapRep.representation(using: .png, properties: [:])
        }
    }

    // MARK: - Capture

    /// Capture a screenshot of the frontmost window.
    /// Returns nil if capture fails (permission denied or no window available).
    func capture() -> CapturedContext? {
        // Get frontmost app
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let appName = frontmostApp?.localizedName
        let frontmostPID = frontmostApp?.processIdentifier

        // Get window info
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        // Find the frontmost window from the frontmost app
        var targetWindowID: CGWindowID?
        var windowTitle: String?

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == frontmostPID,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 // Normal window layer
            else { continue }

            if let windowID = window[kCGWindowNumber as String] as? CGWindowID {
                targetWindowID = windowID
                windowTitle = window[kCGWindowName as String] as? String
                break
            }
        }

        guard let windowID = targetWindowID else {
            // No window found for the frontmost app
            return nil
        }

        // Capture the screenshot
        guard let screenshot = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        // Verify the screenshot is not blank (permission check)
        guard screenshot.width > 0 && screenshot.height > 0 else {
            return nil
        }

        return CapturedContext(
            screenshot: screenshot,
            appName: appName,
            windowTitle: windowTitle
        )
    }

}
