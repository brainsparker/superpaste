import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Resolves virtual key codes against the user's CURRENT keyboard layout.
///
/// Hardcoding key code 9 assumes ANSI QWERTY: on Dvorak that physical key
/// types "x" and the key that types "v" is elsewhere, so both the hotkey
/// trigger and the synthetic ⌘V paste hit the wrong keys. Scanning the active
/// layout with UCKeyTranslate finds the key code that actually produces a
/// given character.
enum KeyboardLayout {
    /// Key code that produces `character` (unmodified) on the current layout,
    /// or nil if the layout has no such key.
    static func keyCode(for character: Character) -> CGKeyCode? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataRef).takeUnretainedValue() as Data

        let target = String(character).lowercased()
        var result: CGKeyCode?

        layoutData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let layoutPtr = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }

            for code in 0..<CGKeyCode(128) {
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0

                let status = UCKeyTranslate(
                    layoutPtr,
                    UInt16(code),
                    UInt16(kUCKeyActionDisplay),
                    0, // no modifiers
                    UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    chars.count,
                    &length,
                    &chars
                )

                guard status == noErr, length > 0 else { continue }
                if String(utf16CodeUnits: chars, count: length).lowercased() == target {
                    result = code
                    return
                }
            }
        }

        return result
    }

    /// Key code for the letter "v" on the current layout, falling back to the
    /// ANSI position when the layout can't be read.
    static var vKeyCode: CGKeyCode {
        keyCode(for: "v") ?? 9
    }
}
