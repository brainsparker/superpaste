import AppKit
import CoreGraphics

/// Service for capturing context from the active window and clipboard.
/// Uses CGWindowListCopyWindowInfo which does NOT require Screen Recording permission
/// for basic window info (name, owner).
final class ContextService {
    static let shared = ContextService()

    private init() {}

    /// Captured context from clipboard and active window
    struct CapturedContext {
        let clipboardText: String?
        let windowTitle: String?
        let appName: String?
        let bundleIdentifier: String?

        var isEmpty: Bool {
            clipboardText == nil && windowTitle == nil && appName == nil
        }

        /// Format context for LLM prompt
        func formatForPrompt() -> String {
            var parts: [String] = []

            if let app = appName {
                parts.append("Application: \(app)")
            }
            if let window = windowTitle, !window.isEmpty {
                parts.append("Window: \(window)")
            }
            if let clipboard = clipboardText, !clipboard.isEmpty {
                parts.append("Clipboard contents:\n\"\"\"\n\(clipboard)\n\"\"\"")
            } else {
                parts.append("Clipboard contents: (empty)")
            }

            return parts.joined(separator: "\n")
        }
    }

    /// Capture current context from clipboard and active window
    func capture() -> CapturedContext {
        // Get clipboard contents
        let clipboardText = ClipboardService.shared.read()

        // Get frontmost app
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let appName = frontmostApp?.localizedName
        let bundleIdentifier = frontmostApp?.bundleIdentifier
        let frontmostPID = frontmostApp?.processIdentifier

        // Get window title using CGWindowListCopyWindowInfo
        // This does NOT require Screen Recording permission for basic info
        var windowTitle: String?

        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            // Find the frontmost window from the frontmost app
            for window in windowList {
                guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                      ownerPID == frontmostPID,
                      let layer = window[kCGWindowLayer as String] as? Int,
                      layer == 0  // Normal window layer
                else { continue }

                // Get window name - available without Screen Recording permission
                if let name = window[kCGWindowName as String] as? String, !name.isEmpty {
                    windowTitle = name
                    break
                }
            }
        }

        return CapturedContext(
            clipboardText: clipboardText,
            windowTitle: windowTitle,
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
    }
}
