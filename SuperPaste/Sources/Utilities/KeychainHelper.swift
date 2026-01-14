import Foundation
import Security

/// Helper for securely storing API keys in the macOS Keychain.
enum KeychainHelper {
    // MARK: - Configuration

    private static let service = "com.superpaste.api"
    private static let account = "anthropic-api-key"

    // MARK: - Errors

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        case deleteFailed(OSStatus)
        case unexpectedData
        case notFound

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Failed to save to Keychain: \(status)"
            case .deleteFailed(let status):
                return "Failed to delete from Keychain: \(status)"
            case .unexpectedData:
                return "Unexpected data format in Keychain"
            case .notFound:
                return "Item not found in Keychain"
            }
        }
    }

    // MARK: - Public API

    /// Save an API key to the Keychain.
    /// If a key already exists, it will be updated.
    static func save(key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        // First try to delete any existing key
        try? delete()

        // Create query for adding
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieve the API key from the Keychain.
    /// Returns nil if no key is stored.
    static func retrieve() -> String? {
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
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    /// Delete the API key from the Keychain.
    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        // errSecItemNotFound is acceptable - means nothing to delete
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if an API key exists in the Keychain.
    static func exists() -> Bool {
        return retrieve() != nil
    }
}
