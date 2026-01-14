import AppKit
import HotKey
import Combine

/// Service for registering and handling global hotkeys.
/// Uses the HotKey package which wraps Carbon APIs.
/// No permissions required.
final class HotkeyService: ObservableObject {
    static let shared = HotkeyService()

    @Published private(set) var isRegistered = false

    /// Publisher that fires when the hotkey is triggered
    let hotkeyTriggered = PassthroughSubject<Void, Never>()

    private var hotKey: HotKey?

    // Default: Option + S
    @Published var keyCombo: KeyCombo = KeyCombo(key: .s, modifiers: .option) {
        didSet {
            if isRegistered {
                unregister()
                register()
            }
        }
    }

    private init() {}

    /// Register the global hotkey
    func register() {
        guard !isRegistered else { return }

        hotKey = HotKey(keyCombo: keyCombo)
        hotKey?.keyDownHandler = { [weak self] in
            self?.hotkeyTriggered.send()
        }

        isRegistered = true
    }

    /// Unregister the global hotkey
    func unregister() {
        hotKey = nil
        isRegistered = false
    }

    /// Update the hotkey combination
    func setKeyCombo(_ combo: KeyCombo) {
        keyCombo = combo
    }
}
