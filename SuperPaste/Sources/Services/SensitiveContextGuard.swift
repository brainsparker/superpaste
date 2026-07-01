import Carbon.HIToolbox
import Foundation

/// Refuses to capture in contexts that are overwhelmingly likely to contain
/// secrets. The privacy pitch has to hold at the worst moment, not the average
/// one: an unlocked password vault or a focused password field must never be
/// screenshotted and shipped to an AI backend.
enum SensitiveContextGuard {
    /// Bundle IDs of password managers and authenticators we refuse to capture.
    private static let defaultBlockedBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.lastpass.lastpassmacdesktop",
        "com.dashlane.dashlanephonefinal",
        "in.sinew.Enpass-Desktop",
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "com.authy.authy-mac",
    ]

    enum Verdict {
        case allowed
        case secureInputActive
        case blockedApp(name: String)
    }

    static func check(bundleIdentifier: String?, appName: String?) -> Verdict {
        // Secure input is what macOS turns on for password fields — if it's
        // active, whatever is focused is a secret.
        if IsSecureEventInputEnabled() {
            return .secureInputActive
        }
        if let bundleID = bundleIdentifier?.lowercased(),
           defaultBlockedBundleIDs.contains(where: { $0.lowercased() == bundleID }) {
            return .blockedApp(name: appName ?? "this app")
        }
        return .allowed
    }
}
