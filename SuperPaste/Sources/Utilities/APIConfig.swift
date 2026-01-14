import Foundation

/// API configuration for Claude Vision.
/// Uses BYOK (Bring Your Own Key) model - user provides their own Anthropic API key.
enum APIConfig {
    // MARK: - Anthropic API Configuration

    static let baseURL = "https://api.anthropic.com/v1/messages"
    static let model = "claude-sonnet-4-20250514"  // Vision-capable model
    static let anthropicVersion = "2023-06-01"

    // MARK: - API Key (BYOK)

    /// Get the API key from Keychain.
    /// Returns nil if no key is configured.
    static var apiKey: String? {
        return KeychainHelper.retrieve()
    }

    /// Check if an API key is configured.
    static var hasAPIKey: Bool {
        guard let key = apiKey else { return false }
        return !key.isEmpty
    }

    /// Save an API key to Keychain.
    static func saveAPIKey(_ key: String) throws {
        try KeychainHelper.save(key: key)
    }

    /// Clear the API key from Keychain.
    static func clearAPIKey() throws {
        try KeychainHelper.delete()
    }

    // MARK: - Request Configuration

    static let timeoutInterval: TimeInterval = 30.0
    static let maxTokens = 1024

    // MARK: - System Prompt

    static let systemPrompt = """
        You are SuperPaste, an AI assistant that generates contextually appropriate text based on what the user is looking at.

        The user pressed a hotkey while viewing their screen. You will receive a screenshot showing what they're looking at. Your job is to figure out what they need and write it.

        ## Common scenarios
        - Email or message visible → Write a reply
        - Question visible → Write an answer
        - Form visible → Suggest what to fill in
        - Document visible → Continue or improve the writing
        - Code visible → Write the next logical code
        - Error message visible → Explain or suggest a fix

        ## Rules
        1. Output ONLY the text to paste—no explanations, no meta-commentary, no markdown formatting unless the context requires it
        2. Match the tone (casual for Slack, professional for email, technical for code)
        3. Be concise unless the context suggests a longer response is needed
        4. If you truly can't figure out what's needed, output: "I couldn't determine what you need from this screen. Try positioning your cursor where you want to type."

        ## Output format
        Raw text, ready to paste. Nothing else.
        """

    // MARK: - Anthropic Console URL

    static let anthropicConsoleURL = URL(string: "https://console.anthropic.com/settings/keys")!
}
