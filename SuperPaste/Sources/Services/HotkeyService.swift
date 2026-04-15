import AppKit
import Combine
import CoreGraphics

/// Service for registering and handling the global Option+V hotkey.
/// Uses a CGEvent tap — reliable on macOS Sequoia without Carbon event loop issues.
final class HotkeyService: ObservableObject {
    static let shared = HotkeyService()

    @Published private(set) var isRegistered = false

    /// Set to true if CGEvent tap creation failed (Accessibility not granted for this binary)
    @Published private(set) var accessibilityPermissionDenied = false

    /// Publisher that fires when the hotkey is triggered
    let hotkeyTriggered = PassthroughSubject<Void, Never>()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    // MARK: - Registration

    func register() {
        guard !isRegistered else { return }

        // Option+V: keycode 9, modifier maskAlternate
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // We need a C-compatible callback. Use a retained pointer to self as userData.
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,             // consumes the event (no "√" typed)
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard type == .keyDown else {
                    return Unmanaged.passRetained(event)
                }
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                // Option+V only — no Cmd, Ctrl, Shift
                let onlyOption = flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift]) == .maskAlternate
                guard keyCode == 9 && onlyOption else {
                    return Unmanaged.passRetained(event)
                }
                // Fire on main thread
                if let ptr = userInfo {
                    let service = Unmanaged<HotkeyService>.fromOpaque(ptr).takeUnretainedValue()
                    DispatchQueue.main.async {
                        service.hotkeyTriggered.send()
                    }
                }
                return nil  // consume — prevents "√" from being typed
            },
            userInfo: selfPtr
        )

        guard let tap else {
            // CGEvent tap creation failed — Accessibility permission not granted for this binary.
            // Release the retained self pointer and signal the failure.
            Unmanaged<HotkeyService>.fromOpaque(selfPtr).release()
            accessibilityPermissionDenied = true
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        isRegistered = true
    }

    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRegistered = false
    }
}
