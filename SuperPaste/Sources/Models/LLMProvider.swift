import Foundation

/// Identifies which AI service powers the paste.
enum LLMProviderID: String, CaseIterable, Identifiable, Codable {
    case superpaste
    case anthropic
    case openai
    case openrouter
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .superpaste: return "SuperPaste (hosted)"
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    var description: String {
        switch self {
        case .superpaste: return "Handled by the SuperPaste backend. Subscription or trial required."
        case .anthropic: return "Screenshots go directly to Anthropic. Uses your Anthropic API key."
        case .openai: return "Screenshots go directly to OpenAI. Uses your OpenAI API key."
        case .openrouter: return "Screenshots go to the model you select via OpenRouter. Uses your OpenRouter API key."
        case .custom: return "Screenshots go to any OpenAI-compatible endpoint. Provide the base URL and API key."
        }
    }

    var isBringYourOwnKey: Bool {
        self != .superpaste
    }

    /// Default model identifier for this provider when a user hasn't set one.
    var defaultModel: String {
        switch self {
        case .superpaste: return "claude-sonnet-5"
        case .anthropic: return "claude-sonnet-4"
        case .openai: return "gpt-4o"
        case .openrouter: return "openai/gpt-4o"
        case .custom: return ""
        }
    }

    var supportsCustomModel: Bool {
        self != .superpaste
    }

    /// The endpoint to POST to (nil for superpaste which uses APIConfig.baseURL).
    var endpointURL: String {
        switch self {
        case .superpaste: return ""
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .openrouter: return "https://openrouter.ai/api/v1/chat/completions"
        case .custom: return "" // user-provided
        }
    }

    /// Link to get an API key.
    var signupURL: URL? {
        switch self {
        case .superpaste: return nil
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .openrouter: return URL(string: "https://openrouter.ai/keys")
        case .custom: return nil
        }
    }
}

/// Persisted user selection for which provider + model to use.
struct LLMProviderConfig: Codable, Equatable {
    var provider: LLMProviderID
    var model: String
    var customEndpoint: String // only for .custom

    static let `default` = LLMProviderConfig(
        provider: .superpaste,
        model: LLMProviderID.superpaste.defaultModel,
        customEndpoint: ""
    )
}

// MARK: - Credential storage

/// Stores the API key for each BYO provider in the Keychain,
/// scoped per provider so switching doesn't lose the saved key.
enum UserCredentialStore {
    private static func keychain(for provider: LLMProviderID) -> Keychain {
        Keychain(service: "app.superpaste.key.\(provider.rawValue)")
    }

    static func apiKey(for provider: LLMProviderID) -> String? {
        guard provider.isBringYourOwnKey else { return nil }
        let kc = keychain(for: provider)
        guard let key = kc.read(), !key.isEmpty else { return nil }
        return key
    }

    static func set(apiKey: String, for provider: LLMProviderID) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard provider.isBringYourOwnKey else { return }
        if trimmed.isEmpty {
            keychain(for: provider).delete()
        } else {
            try keychain(for: provider).write(trimmed)
        }
    }

    static func clear(for provider: LLMProviderID) {
        guard provider.isBringYourOwnKey else { return }
        keychain(for: provider).delete()
    }

    /// True when ANY BYO provider has a key saved. Used to know if we should
    /// skip trial enforcement in the state machine.
    static var anyKeyActive: Bool {
        for provider in LLMProviderID.allCases where provider.isBringYourOwnKey {
            if apiKey(for: provider) != nil { return true }
        }
        return false
    }

    /// The provider that currently has an active API key, or nil.
    static var activeProvider: LLMProviderID? {
        for provider in LLMProviderID.allCases where provider.isBringYourOwnKey {
            if apiKey(for: provider) != nil { return provider }
        }
        return nil
    }
}