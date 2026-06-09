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

// MARK: - Tiny Keychain wrapper

/// Minimal kSecClassGenericPassword wrapper, scoped to a single account.
private struct Keychain {
    let service: String
    let account = "default"

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func write(_ value: String) throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
            return
        }
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
