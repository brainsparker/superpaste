import Foundation

/// Phrase pools for each HUD stage.
enum HUDPhrases {

    // MARK: - Phrase Pools

    static let gathering: [String] = [
        "Reading the room.",
        "Getting the picture.",
        "Taking in the context.",
        "Looking around.",
        "Scanning the scene."
    ]

    static let thinking: [String] = [
        "Writing...",
        "Thinking this through.",
        "Working on it.",
        "One moment.",
        "Almost there."
    ]

    static let ready: [String] = [
        "Done."
    ]

    // MARK: - Actionable Error Messages

    /// Maps error context keywords to user-friendly recovery messages.
    static func actionableError(for message: String) -> String {
        let lower = message.lowercased()

        if lower.contains("timeout") || lower.contains("timed out") {
            return "Took too long \u{2014} try again with a simpler screen."
        }
        if lower.contains("network") || lower.contains("connect") || lower.contains("offline") {
            return "Can't reach the server \u{2014} check your internet connection."
        }
        if lower.contains("api key") || lower.contains("unauthorized") || lower.contains("401") {
            return "Authentication issue \u{2014} check your API key in settings."
        }
        if lower.contains("rate limit") || lower.contains("429") {
            return "Too many requests \u{2014} wait a moment and try again."
        }
        if lower.contains("capture") || lower.contains("screenshot") {
            return "Couldn't capture your screen \u{2014} check Screen Recording permission."
        }
        if lower.contains("permission") || lower.contains("accessibility") {
            return "Missing permission \u{2014} open Settings to re-enable."
        }
        if lower.contains("server") || lower.contains("500") || lower.contains("502") || lower.contains("503") {
            return "Server hiccup \u{2014} try again in a few seconds."
        }

        // Fallback
        return "Something went wrong \u{2014} try again."
    }

    // MARK: - Random Selection with No Repeat

    private static var lastGathering: String?
    private static var lastThinking: String?
    private static var lastReady: String?

    /// Get a random gathering phrase (won't repeat the last one)
    static func randomGathering() -> String {
        let available = gathering.filter { $0 != lastGathering }
        let phrase = available.randomElement() ?? gathering[0]
        lastGathering = phrase
        return phrase
    }

    /// Get a random thinking phrase (won't repeat the last one)
    static func randomThinking() -> String {
        let available = thinking.filter { $0 != lastThinking }
        let phrase = available.randomElement() ?? thinking[0]
        lastThinking = phrase
        return phrase
    }

    /// Get a random ready phrase (won't repeat the last one)
    static func randomReady() -> String {
        let available = ready.filter { $0 != lastReady }
        let phrase = available.randomElement() ?? ready[0]
        lastReady = phrase
        return phrase
    }

    /// Get an actionable error phrase based on the error context
    static func randomError(context: String = "") -> String {
        actionableError(for: context)
    }

    /// Reset last-used tracking (useful for testing)
    static func reset() {
        lastGathering = nil
        lastThinking = nil
        lastReady = nil
    }
}
