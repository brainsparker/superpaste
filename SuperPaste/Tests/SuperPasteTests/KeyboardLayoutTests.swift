import Testing
@testable import SuperPaste

struct KeyboardLayoutTests {

    @Test func vKeyCodeReturnsAValue() {
        // On any macOS layout there is a key for "v". Should never be 0 or 127+.
        let code = KeyboardLayout.vKeyCode
        // Valid key codes are 0–127; 9 is the ANSI QWERTY fallback
        #expect(code >= 0)
        #expect(code <= 127)
    }

    @Test func keyCodeForVIsConsistent() {
        // keyCode(for:) and vKeyCode resolve from the same layout.
        #expect(KeyboardLayout.keyCode(for: "v") == KeyboardLayout.vKeyCode)
    }

    @Test func keyCodeForLowerAndUpperCaseAreSame() {
        // UCKeyTranslate with no modifiers should map both cases identically.
        #expect(
            KeyboardLayout.keyCode(for: "v") == KeyboardLayout.keyCode(for: "V")
        )
    }

    @Test func keyCodeForUnknownCharacterIsNil() {
        // No keyboard layout has a key for an emoji.
        #expect(KeyboardLayout.keyCode(for: "\u{1F600}") == nil)
    }
}