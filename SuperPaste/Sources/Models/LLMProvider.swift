import Foundation

/// Identifies which AI service powers the paste.
enum LLMProviderID: String, CaseIterable, Identifiable, Codable {
    case superpaste
    case anthropic
    case openai
    case openrouter
    case ollama
    case lmstudio
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .superpaste: return "SuperPaste (hosted)"
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .ollama: return "Ollama (local)"
        case .lmstudio: return "LM Studio (local)"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    var description: String {
        switch self {
        case .superpaste: return "Handled by the SuperPaste backend. Subscription or trial required."
        case .anthropic: return "Screenshots go directly to Anthropic. Uses your Anthropic API key."
        case .openai: return "Screenshots go directly to OpenAI. Uses your OpenAI API key."
        case .openrouter: return "Screenshots go to the model you select via OpenRouter. Uses your OpenRouter API key."
        case .ollama: return "Runs on this Mac through Ollama. Screenshots never leave your computer. No API key, no account."
        case .lmstudio: return "Runs on this Mac through LM Studio's local server. Screenshots never leave your computer. No API key, no account."
        case .custom: return "Screenshots go to any OpenAI-compatible endpoint. Provide the base URL; the API key is optional for servers that don't need one."
        }
    }

    var isBringYourOwnKey: Bool {
        self != .superpaste
    }

    /// Local inference servers run on this Mac and are configured by endpoint
    /// rather than by credential.
    var isLocal: Bool {
        self == .ollama || self == .lmstudio
    }

    /// Whether a saved API key is mandatory before the provider can be used.
    /// Local servers (Ollama, LM Studio) accept requests without one, and a
    /// custom endpoint may or may not be protected, so the key is optional there.
    var requiresAPIKey: Bool {
        switch self {
        case .superpaste, .ollama, .lmstudio, .custom: return false
        case .anthropic, .openai, .openrouter: return true
        }
    }

    /// Whether the user can edit the endpoint URL.
    var supportsCustomEndpoint: Bool {
        isLocal || self == .custom
    }

    /// Whether the endpoint exposes an OpenAI-style `GET /v1/models` list that
    /// the Settings model picker can read.
    var supportsModelDiscovery: Bool {
        supportsCustomEndpoint
    }

    /// Default model identifier for this provider when a user hasn't set one.
    /// Local providers leave this empty: the model is picked from whatever the
    /// server actually has installed (see `LocalModelServer.pickDefaultModel`).
    var defaultModel: String {
        switch self {
        case .superpaste: return "claude-sonnet-5"
        case .anthropic: return "claude-sonnet-4"
        case .openai: return "gpt-4o"
        case .openrouter: return "openai/gpt-4o"
        case .ollama, .lmstudio, .custom: return ""
        }
    }

    var supportsCustomModel: Bool {
        self != .superpaste
    }

    /// The endpoint to POST to (empty for superpaste, which uses APIConfig.baseURL,
    /// and for custom, where the user supplies it). Local providers return the
    /// server's default chat-completions URL; the user can override it.
    var endpointURL: String {
        switch self {
        case .superpaste: return ""
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .openrouter: return "https://openrouter.ai/api/v1/chat/completions"
        case .ollama: return "http://localhost:11434/v1/chat/completions"
        case .lmstudio: return "http://localhost:1234/v1/chat/completions"
        case .custom: return "" // user-provided
        }
    }

    /// Placeholder shown in the endpoint field.
    var endpointPlaceholder: String {
        switch self {
        case .ollama: return "http://localhost:11434"
        case .lmstudio: return "http://localhost:1234"
        default: return "https://your-endpoint.com/v1/chat/completions"
        }
    }

    /// Example model identifiers shown under the model field.
    var modelHint: String {
        switch self {
        case .ollama: return "Vision models work best: qwen3-vl, gemma4, llama3.2-vision. Pull one with `ollama pull qwen3-vl`."
        case .lmstudio: return "Load a vision-capable model in LM Studio (Qwen3-VL, Gemma 4) and start the local server."
        case .custom: return "e.g. gpt-4o, claude-sonnet-4, gemini-2.5-flash"
        default: return "Leave empty for the default. e.g. \(defaultModel)"
        }
    }

    /// Link to get an API key, or to install the local server.
    var signupURL: URL? {
        switch self {
        case .superpaste: return nil
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .openrouter: return URL(string: "https://openrouter.ai/keys")
        case .ollama: return URL(string: "https://ollama.com/download")
        case .lmstudio: return URL(string: "https://lmstudio.ai")
        case .custom: return nil
        }
    }

    /// Label for the `signupURL` link.
    var signupLabel: String {
        switch self {
        case .ollama: return "Install Ollama"
        case .lmstudio: return "Install LM Studio"
        default: return "Get a \(displayName) API key"
        }
    }
}

/// Persisted user selection for which provider + model to use.
struct LLMProviderConfig: Codable, Equatable {
    var provider: LLMProviderID
    var model: String
    /// Endpoint override. Used by `.custom` (required) and by local providers
    /// (optional; empty means the server's default port on localhost).
    var customEndpoint: String

    static let `default` = LLMProviderConfig(
        provider: .superpaste,
        model: LLMProviderID.superpaste.defaultModel,
        customEndpoint: ""
    )

    /// The chat-completions URL this configuration will POST to, or nil when
    /// the provider needs an endpoint the user hasn't supplied yet.
    var resolvedEndpoint: String? {
        if provider.supportsCustomEndpoint {
            let trimmed = customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return provider.isLocal ? provider.endpointURL : nil
            }
            return LocalEndpoint.chatCompletionsURL(from: trimmed)
        }
        return provider.endpointURL.isEmpty ? nil : provider.endpointURL
    }

    /// True when the selected provider has everything it needs to serve a
    /// paste without the hosted backend: a bring-your-own provider with an
    /// endpoint and, where the provider demands one, a saved API key.
    var isOwnProviderReady: Bool {
        guard provider.isBringYourOwnKey else { return false }
        guard resolvedEndpoint != nil else { return false }
        if provider.requiresAPIKey {
            return UserCredentialStore.apiKey(for: provider) != nil
        }
        return true
    }
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

    /// True when ANY BYO provider has a key saved.
    static var anyKeyActive: Bool {
        for provider in LLMProviderID.allCases where provider.isBringYourOwnKey {
            if apiKey(for: provider) != nil { return true }
        }
        return false
    }

    /// The provider that will actually serve the next paste outside the hosted
    /// backend, or nil when the hosted backend (trial or license) is in use.
    /// Keyless local servers count: a saved key is not what makes them active.
    static func activeProvider(for config: LLMProviderConfig) -> LLMProviderID? {
        config.isOwnProviderReady ? config.provider : nil
    }

    /// Convenience over the persisted configuration.
    static var activeProvider: LLMProviderID? {
        activeProvider(for: LLMService.currentConfig())
    }
}
