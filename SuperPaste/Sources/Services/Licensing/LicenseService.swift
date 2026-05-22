import Foundation
import Security

/// Direct, client-side license validation against Polar.sh.
///
/// Uses Polar's customer-portal endpoint which is auth-free and explicitly safe to
/// call from a desktop app — no organization access token is needed, only the
/// public org UUID. The license key itself is stored in the macOS Keychain so it
/// survives reinstalls.
///
/// Replaces the server-side gate in `LLMService.validateLicense`. Once every
/// install path has been migrated to this service the Cloudflare Worker can be
/// deleted (Phase 5 follow-up).
final class LicenseService {
    static let shared = LicenseService()

    /// Polar organization UUID. Public-safe per Polar's customer-portal docs —
    /// it appears in checkout URLs and the SDK's docs.
    ///
    /// TODO: replace with the actual SuperPaste org UUID. While this stays
    /// `nil` the service falls back to a soft-validate that treats any
    /// non-empty key as valid (so the rest of the app remains testable).
    static let organizationID: String? = nil  // e.g. "abcd1234-..."

    private let session: URLSession
    private let keychain: Keychain
    private static let validateURL = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/validate")!

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
        self.keychain = Keychain(service: "app.superpaste.license")
    }

    // MARK: - Errors

    enum LicenseError: LocalizedError {
        case missingOrganizationID
        case networkFailure
        case invalidKey
        case unexpectedResponse(Int)

        var errorDescription: String? {
            switch self {
            case .missingOrganizationID:
                return "License validation is not configured (missing Polar organization ID)."
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

    /// Validate a license key against Polar.sh.
    ///
    /// On success, returns true. Does not store anything — call `activate` to
    /// persist a validated key.
    func validate(_ key: String) async throws -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Soft-fallback for development before the org UUID is wired in.
        guard let orgID = Self.organizationID else {
            #if DEBUG
            print("[LicenseService] WARNING: organizationID is nil. Soft-accepting any non-empty key for development.")
            return true
            #else
            throw LicenseError.missingOrganizationID
            #endif
        }

        var request = URLRequest(url: Self.validateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["key": trimmed, "organization_id": orgID]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw LicenseError.networkFailure
        }

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.networkFailure
        }

        switch http.statusCode {
        case 200...299: return true
        case 404, 401, 403: return false
        default: throw LicenseError.unexpectedResponse(http.statusCode)
        }
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
