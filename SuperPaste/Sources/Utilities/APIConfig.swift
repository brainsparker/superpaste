import Foundation

/// API configuration for SuperPaste.
enum APIConfig {
    // MARK: - Endpoint

    /// SuperPaste proxy endpoint — Anthropic auth lives server-side.
    #if DEBUG
    static let baseURL = "http://localhost:8787/v1/messages"
    #else
    static let baseURL = "https://superpaste-api.brianjsparker.workers.dev/v1/messages"
    #endif

    // MARK: - Request Configuration

    static let timeoutInterval: TimeInterval = 30.0
    static let maxTokens = 1024

    // MARK: - System Prompt

    private static let baseSystemPrompt = """
        You are SuperPaste, an AI assistant that generates contextually appropriate text based on what the user is looking at.

        The user pressed a hotkey while viewing their screen. You will receive a screenshot showing what they're looking at. Your job is to figure out what they need and write it.

        ## Common scenarios
        - Email or message visible \u{2192} Write a reply
        - Question visible \u{2192} Write an answer
        - Form visible \u{2192} Suggest what to fill in
        - Document visible \u{2192} Continue or improve the writing
        - Code visible \u{2192} Write the next logical code
        - Error message visible \u{2192} Explain or suggest a fix

        ## Rules
        1. Output ONLY the text to paste\u{2014}no explanations, no meta-commentary, no markdown formatting unless the context requires it
        2. Be concise unless the context suggests a longer response is needed
        3. If you truly can't figure out what's needed, output: "I couldn't determine what you need from this screen. Try positioning your cursor where you want to type."

        ## Output format
        Raw text, ready to paste. Nothing else.
        """

    /// Build the full system prompt incorporating user preferences.
    static var systemPrompt: String {
        let tone = ResponseTone(rawValue: UserDefaults.standard.string(forKey: "responseTone") ?? ResponseTone.matchContext.rawValue) ?? .matchContext
        let length = ResponseLength(rawValue: UserDefaults.standard.string(forKey: "responseLength") ?? ResponseLength.balanced.rawValue) ?? .balanced

        var prompt = baseSystemPrompt

        prompt += "\n\n## Tone\n\(tone.promptFragment)"
        prompt += "\n\n## Length\n\(length.promptFragment)"

        return prompt
    }
}
