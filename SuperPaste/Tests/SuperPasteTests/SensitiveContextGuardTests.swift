import Testing
@testable import SuperPaste

struct SensitiveContextGuardTests {

    @Test func allowsUnknownBundle() {
        let verdict = SensitiveContextGuard.check(
            bundleIdentifier: "com.example.unknown",
            appName: "Random App"
        )
        if case .allowed = verdict {
            // Pass
        } else {
            Issue.record("Expected .allowed, got \(verdict)")
        }
    }

    @Test func allowsNilBundle() {
        let verdict = SensitiveContextGuard.check(
            bundleIdentifier: nil,
            appName: "Some App"
        )
        if case .allowed = verdict {
            // Pass
        } else {
            Issue.record("Expected .allowed, got \(verdict)")
        }
    }

    @Test func blocks1Password() {
        let verdict = SensitiveContextGuard.check(
            bundleIdentifier: "com.1password.1password",
            appName: "1Password"
        )
        if case .blockedApp(let name) = verdict {
            #expect(name == "1Password")
        } else {
            Issue.record("Expected .blockedApp, got \(verdict)")
        }
    }

    @Test func blocksBitwarden() {
        let verdict = SensitiveContextGuard.check(
            bundleIdentifier: "com.bitwarden.desktop",
            appName: "Bitwarden"
        )
        if case .blockedApp(let name) = verdict {
            #expect(name == "Bitwarden")
        } else {
            Issue.record("Expected .blockedApp, got \(verdict)")
        }
    }

    @Test func blocksApplePasswords() {
        let verdict = SensitiveContextGuard.check(
            bundleIdentifier: "com.apple.Passwords",
            appName: "Passwords"
        )
        if case .blockedApp(let name) = verdict {
            #expect(name == "Passwords")
        } else {
            Issue.record("Expected .blockedApp, got \(verdict)")
        }
    }

    @Test func blocksCaseInsensitively() {
        let verdict = SensitiveContextGuard.check(
            bundleIdentifier: "COM.1PASSWORD.1PASSWORD",
            appName: "1Password"
        )
        if case .blockedApp = verdict {
            // Pass
        } else {
            Issue.record("Expected .blockedApp, got \(verdict)")
        }
    }
}