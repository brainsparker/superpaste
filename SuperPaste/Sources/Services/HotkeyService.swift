import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics

/// The hotkey combinations SuperPaste can trigger on. All use the key that
/// types "v" on the user's current layout, resolved via KeyboardLayout.
enum HotkeyPreset: String, CaseIterable, Identifiable {
    case optionV
    case controlOptionV
    case commandShiftV

    var id: String { rawValue }

    static var current: HotkeyPreset {
        HotkeyPreset(rawValue: UserDefaults.standard.string(forKey: "hotkeyPreset") ?? "") ?? .optionV
    }

    var displayName: String {
        switch self {
        case .optionV: return "\u{2325} Option + V"
        case .controlOptionV: return "\u{2303} Control + \u{2325} Option + V"
        case .commandShiftV: return "\u{2318} Command + \u{21E7} Shift + V"
        }
    }

    /// Short form for HUD/menu copy.
    var shortName: String {
        switch self {
        case .optionV: return "\u{2325}V"
        case .controlOptionV: return "\u{2303}\u{2325}V"
        case .commandShiftV: return "\u{2318}\u{21E7}V"
        }
    }

    var flags: CGEventFlags {
        switch self {
        case .optionV: return .maskAlternate
        case .controlOptionV: return [.maskControl, .maskAlternate]
        case .commandShiftV: return [.maskCommand, .maskShift]
        }
    }
}

/// Service for registering and handling the global hotkey.
/// Uses a CGEvent tap — reliable on macOS Sequoia without Carbon event loop issues.
final class HotkeyService: ObservableObject {
    static let shared = HotkeyService()

    @Published private(set) var isRegistered = false

    /// Set to true if CGEvent tap creation failed (Accessibility not granted for this binary)
    @Published private(set) var accessibilityPermissionDenied = false

    /// Publisher that fires when the hotkey is triggered
    let hotkeyTriggered = PassthroughSubject<Void, Never>()

    /// Fires when Esc is pressed while `escapeInterceptor` returns true
    /// (i.e. a paste is in flight and the user wants to cancel it).
    let escapePressed = PassthroughSubject<Void, Never>()

    /// Queried on the main run loop for every Esc key-down; return true to
    /// swallow the event and emit `escapePressed`. Set by AppState.
    var escapeInterceptor: (() -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Key code that types "v" on the current layout, cached because scanning
    /// the layout per keystroke would stall the tap (macOS kills stalled taps).
    private var vKeyCode: CGKeyCode = 9

    private let escapeKeyCode: CGKeyCode = 53
    private let modifierMask: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]

    private init() {
        refreshLayoutKeyCode()
        // Re-resolve when the user switches keyboard layouts.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(keyboardLayoutChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
    }

    @objc private func keyboardLayoutChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshLayoutKeyCode()
        }
    }

    private func refreshLayoutKeyCode() {
        vKeyCode = KeyboardLayout.vKeyCode
    }

    // MARK: - Registration

    func register() {
        guard !isRegistered else { return }
        refreshLayoutKeyCode()

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // Singleton lifetime covers the event tap; use an unretained pointer to avoid leaking self.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,             // consumes the event (no "√" typed)
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let ptr = userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let service = Unmanaged<HotkeyService>.fromOpaque(ptr).takeUnretainedValue()

                // macOS disables taps whose callback stalls (or on user input for
                // some tap types). Without this branch the hotkey silently dies
                // until the app is relaunched.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = service.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard type == .keyDown else {
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags.intersection(service.modifierMask)
                let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

                // Esc cancels an in-flight paste. Only intercepted while
                // processing, so Esc behaves normally the rest of the time.
                if keyCode == service.escapeKeyCode, flags.isEmpty,
                   service.escapeInterceptor?() == true {
                    DispatchQueue.main.async {
                        service.escapePressed.send()
                    }
                    return nil
                }

                guard keyCode == service.vKeyCode, flags == HotkeyPreset.current.flags else {
                    return Unmanaged.passUnretained(event)
                }

                // Holding the hotkey shouldn't fire repeatedly — consume the
                // autorepeat so it doesn't type stray characters either.
                if !isAutorepeat {
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
            accessibilityPermissionDenied = true
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        isRegistered = true
        accessibilityPermissionDenied = false
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

    /// Tear down and recreate the tap. Needed after Accessibility is revoked
    /// and re-granted: `isRegistered` stays true but the old tap is dead.
    func reRegister() {
        unregister()
        register()
    }
}
