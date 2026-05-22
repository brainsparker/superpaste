import Foundation

/// API configuration for SuperPaste.
enum APIConfig {
    // MARK: - Endpoint

    /// SuperPaste proxy endpoint — Anthropic auth lives server-side.
    /// Slated for deletion in Phase 3 (LocalInferenceService replacement).
    #if DEBUG
    static let baseURL = "http://localhost:8787/v1/messages"
    #else
    static let baseURL = "https://superpaste-api.brianjsparker.workers.dev/v1/messages"
    #endif

    // MARK: - Request Configuration

    static let timeoutInterval: TimeInterval = 30.0
    static let maxTokens = 1024

    // MARK: - System Prompt

    static func buildSystemPrompt(
        personalContext: String,
        tone: ResponseTone = .matchContext,
        length: ResponseLength = .balanced
    ) -> String {
        let trimmed = personalContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextSection = trimmed.isEmpty ? "" : """


        ## About the user
        \(trimmed)
        """

        return """
        You are SuperPaste, an AI assistant that generates contextually appropriate text based on what the user is looking at.

        The user pressed a hotkey while viewing their screen. You will receive a screenshot showing what they're looking at. Your job is to figure out what they need and write it.

        ## Common scenarios
        - Email or message visible \u{2192} Write a reply
        - Question visible \u{2192} Write an answer
        - Form visible \u{2192} Suggest what to fill in
        - Document visible \u{2192} Continue or improve the writing
        - Code visible \u{2192} Write the next logical code
        - Error message visible \u{2192} Explain or suggest a fix

        ## Tone
        \(tone.promptFragment)

        ## Length
        \(length.promptFragment)

        ## Rules
        1. Output ONLY the text to paste\u{2014}no explanations, no meta-commentary, no markdown formatting unless the context requires it
        2. If you truly can't figure out what's needed, output: "I couldn't determine what you need from this screen. Try positioning your cursor where you want to type."\(contextSection)

        ## Output format
        Raw text, ready to paste. Nothing else.
        """
    }
}
