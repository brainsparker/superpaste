import Foundation
import Security

/// License validation via the SuperPaste backend.
///
/// Validation goes through the Worker's `/v1/validate-license` endpoint rather
/// than Polar directly: the Worker holds the Polar credentials and also honors
/// the owner bypass key, so the app needs no Polar configuration at all. The
/// license key itself is stored in the macOS Keychain so it survives reinstalls.
final class LicenseService {
    static let shared = LicenseService()

    private let session: URLSession
    private let keychain: Keychain
    private static let validateURL = URL(string: APIConfig.validateLicenseURL)!

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
        self.keychain = Keychain(service: "app.superpaste.license")
    }

    // MARK: - Errors

    enum LicenseError: LocalizedError {
        case networkFailure
        case invalidKey
        case unexpectedResponse(Int)

        var errorDescription: String? {
            switch self {
            case .networkFailure:
                return "Couldn't reach the license server. Check your internet connection."
            case .invalidKey:
                return "That license key is not valid."
            case .unexpectedResponse(let status):
                return "Unexpected response from license server (\(status))."
            }
        }
    }

    // MARK: - Public API

    /// Current license key stored in the Keychain, if any.
    var currentLicenseKey: String? {
        keychain.read()
    }

    /// True if a license key is on record locally. This does NOT re-validate
    /// online — call `validate` for that.
    var hasLocalLicense: Bool {
        currentLicenseKey != nil
    }

    /// Validate a license key against the SuperPaste backend.
    ///
    /// On success, returns true. Does not store anything — call `activate` to
    /// persist a validated key.
    func validate(_ key: String) async throws -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var request = URLRequest(url: Self.validateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["key": trimmed])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LicenseError.networkFailure
        }

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.networkFailure
        }

        guard (200...299).contains(http.statusCode) else {
            throw LicenseError.unexpectedResponse(http.statusCode)
        }

        struct ValidateResponse: Decodable { let valid: Bool }
        guard let decoded = try? JSONDecoder().decode(ValidateResponse.self, from: data) else {
            throw LicenseError.unexpectedResponse(http.statusCode)
        }
        return decoded.valid
    }

    /// Validate `key` and, on success, persist it to the Keychain.
    func activate(_ key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = try await validate(trimmed)
        guard valid else { throw LicenseError.invalidKey }
        try keychain.write(trimmed)
    }

    /// Remove any stored license key.
    func deactivate() {
        keychain.delete()
    }

    /// One-time migration from the legacy `UserDefaults["licenseKey"]` storage.
    ///
    /// Idempotent: if a Keychain entry already exists, nothing happens.
    /// If the migration succeeds, the UserDefaults entry is removed.
    func migrateFromUserDefaultsIfNeeded() {
        guard !hasLocalLicense else { return }
        guard let legacy = UserDefaults.standard.string(forKey: "licenseKey"),
              !legacy.isEmpty else { return }
        do {
            try keychain.write(legacy)
            UserDefaults.standard.removeObject(forKey: "licenseKey")
        } catch {
            // Leave UserDefaults in place — next launch can retry.
        }
    }
}

// Keychain wrapper lives in Sources/Utilities/Keychain.swift (shared with UserAPIKey).
