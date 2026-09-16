import AppKit
import ApplicationServices

struct PasteDestination {
    let pid: pid_t
    let window: AXUIElement
    let field: AXUIElement

    static func current() -> Self? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        guard let window = element(app, attribute: kAXFocusedWindowAttribute),
              let field = element(app, attribute: kAXFocusedUIElementAttribute),
              let role = value(field, attribute: kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              value(field, attribute: kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              value(field, attribute: kAXEnabledAttribute) as? Bool != false else { return nil }
        return Self(pid: pid, window: window, field: field)
    }

    func isStillFocused() -> Bool {
        guard let current = Self.current() else { return false }
        return pid == current.pid && CFEqual(window, current.window) && CFEqual(field, current.field)
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
