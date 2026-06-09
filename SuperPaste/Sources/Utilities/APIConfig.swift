import Foundation

/// API configuration for SuperPaste.
enum APIConfig {
    // MARK: - Endpoint

    /// SuperPaste backend endpoint — model auth lives server-side.
    #if DEBUG
    static let baseURL = "http://localhost:8787/v1/messages"
    static let validateLicenseURL = "http://localhost:8787/v1/validate-license"
    #else
    static let baseURL = "https://superpaste-api.brianjsparker.workers.dev/v1/messages"
    static let validateLicenseURL = "https://superpaste-api.brianjsparker.workers.dev/v1/validate-license"
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
        You are SuperPaste, an AI assistant that generates contextually appropriate text from the user's active-window context.

        The user placed their cursor, pressed Option V, and SuperPaste captured one screenshot of the active window. Your job is to figure out what text belongs in the focused field and write it.

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
        2. If you truly can't figure out what's needed, output: "I couldn't determine what you need from this active window. Try positioning your cursor where you want to type."\(contextSection)

        ## Output format
        Raw text, ready to paste. Nothing else.
        """
    }
}
