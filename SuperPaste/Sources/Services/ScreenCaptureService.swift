import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Service for capturing screenshots of the active window.
/// Requires Screen Recording permission.
final class ScreenCaptureService {
    static let shared = ScreenCaptureService()

    private init() {}

    // MARK: - Types

    /// Why a capture produced nothing — each case gets its own user-facing
    /// message. Reporting every failure as "check Screen Recording permission"
    /// sends users into System Settings to debug problems that aren't there.
    enum CaptureError: Error {
        /// Frontmost app is SuperPaste itself and self-capture isn't allowed.
        case ownWindowOnly
        /// The frontmost app has no capturable window.
        case noWindow
        /// The window captured as a solid black frame (DRM, iPhone Mirroring).
        case blackFrame
        /// The actual screenshot call failed — this one IS likely permissions.
        case captureFailed
    }

    /// Captured context containing screenshot and metadata.
    struct CapturedContext {
        let screenshot: CGImage
        let appName: String?
        let bundleIdentifier: String?
        let windowTitle: String?
        /// PID of the app that was frontmost at capture time — re-checked
        /// before the synthetic paste so the response can't land in a
        /// different app the user switched to mid-request.
        let frontmostPID: pid_t?

        /// Longest edge sent upstream. Anthropic downscales past ~1568px
        /// anyway, so bigger uploads buy latency and cost, not quality.
        static let maxDimension: CGFloat = 1568
        private static let jpegQuality: CGFloat = 0.8

        /// Downscaled, JPEG-compressed, base64-encoded screenshot.
        /// A full-Retina lossless PNG of a 5K window can run tens of MB;
        /// this typically lands in the 150–400KB range.
        func base64EncodedJPEG() -> String? {
            jpegData()?.base64EncodedString()
        }

        func jpegData() -> Data? {
            let scaled = Self.downscaled(screenshot, maxDimension: Self.maxDimension) ?? screenshot
            let bitmapRep = NSBitmapImageRep(cgImage: scaled)
            return bitmapRep.representation(
                using: .jpeg,
                properties: [.compressionFactor: Self.jpegQuality]
            )
        }

        private static func downscaled(_ image: CGImage, maxDimension: CGFloat) -> CGImage? {
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)
            let longest = max(width, height)
            guard longest > maxDimension else { return image }

            let scale = maxDimension / longest
            let newWidth = Int(width * scale)
            let newHeight = Int(height * scale)

            guard let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
            return context.makeImage()
        }
    }

    // MARK: - Capture

    /// Capture a screenshot of the frontmost window.
    /// - Parameter allowOwnWindow: permit capturing SuperPaste's own window —
    ///   only the onboarding practice moment wants that.
    func capture(allowOwnWindow: Bool = false) async throws -> CapturedContext {
        // Get frontmost app
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let appName = frontmostApp?.localizedName
        let bundleIdentifier = frontmostApp?.bundleIdentifier
        let frontmostPID = frontmostApp?.processIdentifier

        if !allowOwnWindow, frontmostPID == getpid() {
            throw CaptureError.ownWindowOnly
        }

        // Get window info
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            throw CaptureError.captureFailed
        }

        // Find the frontmost window from the frontmost app
        var targetWindowID: CGWindowID?
        var windowTitle: String?
        let ownPID = getpid()

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == frontmostPID,
                  // Never screenshot SuperPaste's own windows (except during
                  // the onboarding practice moment, which captures itself).
                  allowOwnWindow || ownerPID != ownPID,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 // Normal window layer
            else { continue }

            // Skip tiny helper windows (tooltips, focus rings, 1px overlays) —
            // first-match on those captures the wrong surface in Electron apps.
            if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
               let w = bounds["Width"], let h = bounds["Height"],
               w < 64 || h < 64 {
                continue
            }

            if let windowID = window[kCGWindowNumber as String] as? CGWindowID {
                targetWindowID = windowID
                windowTitle = window[kCGWindowName as String] as? String
                break
            }
        }

        guard let windowID = targetWindowID else {
            throw CaptureError.noWindow
        }

        // ScreenCaptureKit is the supported path on macOS 14+; the legacy
        // CGWindowList capture stays as a fallback because SCK can fail
        // transiently (shareable-content lookups race window closes).
        var screenshot = await captureWithScreenCaptureKit(windowID: windowID)
        if screenshot == nil {
            screenshot = legacyCapture(windowID: windowID)
        }

        guard let screenshot, screenshot.width > 0, screenshot.height > 0 else {
            throw CaptureError.captureFailed
        }

        // DRM-protected content and iPhone-Mirroring windows capture as solid
        // black; sending that upstream produces a hallucinated paste.
        if Self.isEffectivelyBlack(screenshot) {
            throw CaptureError.blackFrame
        }

        return CapturedContext(
            screenshot: screenshot,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            frontmostPID: frontmostPID
        )
    }

    // MARK: - Capture backends

    private func captureWithScreenCaptureKit(windowID: CGWindowID) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            configuration.showsCursor = false

            // Capture straight at (or below) the upload resolution instead of
            // grabbing full Retina pixels and throwing most of them away.
            let pixelScale = CGFloat(filter.pointPixelScale)
            let pixelWidth = filter.contentRect.width * pixelScale
            let pixelHeight = filter.contentRect.height * pixelScale
            let longest = max(pixelWidth, pixelHeight)
            let scale = longest > CapturedContext.maxDimension
                ? CapturedContext.maxDimension / longest
                : 1
            configuration.width = max(1, Int(pixelWidth * scale))
            configuration.height = max(1, Int(pixelHeight * scale))

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            return nil
        }
    }

    /// Deprecated API kept only as a fallback for SCK failures.
    @available(macOS, deprecated: 14.0)
    private func legacyCapture(windowID: CGWindowID) -> CGImage? {
        CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
    }

    // MARK: - Blank detection

    /// True when the frame is uniformly near-black (DRM / mirroring capture).
    /// Deliberately does NOT reject uniform light frames — an empty white
    /// document is a legitimate capture.
    private static func isEffectivelyBlack(_ image: CGImage) -> Bool {
        let sample = 8
        var pixels = [UInt8](repeating: 0, count: sample * sample * 4)
        guard let context = CGContext(
            data: &pixels,
            width: sample,
            height: sample,
            bitsPerComponent: 8,
            bytesPerRow: sample * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: sample, height: sample))

        var maxLuminance: UInt8 = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let luminance = max(pixels[i], pixels[i + 1], pixels[i + 2])
            maxLuminance = max(maxLuminance, luminance)
            if maxLuminance > 16 { return false }
        }
        return true
    }
}
