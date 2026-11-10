import AppKit
import ApplicationServices

struct PasteDestination {
    let pid: pid_t
    let window: AXUIElement
    let field: AXUIElement
    let windowID: CGWindowID
    let insertion: InsertionContext
    let windowTitle: String?

    static func current() -> Self? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        guard let window = element(app, attribute: kAXFocusedWindowAttribute),
              let field = element(app, attribute: kAXFocusedUIElementAttribute),
              let role = value(field, attribute: kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              value(field, attribute: kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              value(field, attribute: kAXEnabledAttribute) as? Bool == true,
              let text = value(field, attribute: kAXValueAttribute) as? String,
              let rangeValue = value(field, attribute: kAXSelectedTextRangeAttribute),
              CFGetTypeID(rangeValue) == AXValueGetTypeID(),
              let windowID = focusedWindowID(window, pid: pid) else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(rangeValue, to: AXValue.self), .cfRange, &range),
              range.location >= 0, range.length >= 0, range.location <= text.utf16.count,
              range.length <= text.utf16.count - range.location else { return nil }
        return Self(pid: pid, window: window, field: field, windowID: windowID,
                    insertion: .init(value: text, selectionLocation: range.location, selectionLength: range.length),
                    windowTitle: value(window, attribute: kAXTitleAttribute) as? String)
    }

    func isStillFocused() -> Bool {
        guard let current = Self.current() else { return false }
        return pid == current.pid && windowID == current.windowID && CFEqual(window, current.window)
            && CFEqual(field, current.field) && insertion == current.insertion && windowTitle == current.windowTitle
    }

    private static func focusedWindowID(_ window: AXUIElement, pid: pid_t) -> CGWindowID? {
        guard let position = value(window, attribute: kAXPositionAttribute),
              let size = value(window, attribute: kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return matchingWindowID(frame: CGRect(origin: point, size: dimensions),
                                title: value(window, attribute: kAXTitleAttribute) as? String,
                                pid: pid, windows: windows)
    }

    static func matchingWindowID(frame: CGRect, title: String?, pid: pid_t, windows: [[String: Any]]) -> CGWindowID? {
        let matches = windows.filter { entry in
            guard entry[kCGWindowOwnerPID as String] as? Int32 == pid,
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let raw = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: raw) else { return false }
            let sameBounds = abs(rect.minX - frame.minX) < 2 && abs(rect.minY - frame.minY) < 2
                && abs(rect.width - frame.width) < 2 && abs(rect.height - frame.height) < 2
            let cgTitle = entry[kCGWindowName as String] as? String
            return sameBounds && (title == nil || cgTitle == nil || title == cgTitle)
        }
        guard matches.count == 1 else { return nil }
        return matches[0][kCGWindowNumber as String] as? CGWindowID
    }

    private static func value(_ element: AXUIElement, attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else {
            return nil
        }
        return result
    }

    private static func element(_ source: AXUIElement, attribute: String) -> AXUIElement? {
        guard let result = value(source, attribute: attribute),
              CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        // AXUIElement has no conditional Swift cast; validate its CF type first.
        return unsafeBitCast(result, to: AXUIElement.self)
    }
}
