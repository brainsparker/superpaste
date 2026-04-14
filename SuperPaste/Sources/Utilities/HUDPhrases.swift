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

    static let error: [String] = [
        "Something went wrong.",
        "Couldn't connect.",
        "Check your API key.",
        "Try again."
    ]

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

    /// Get a random error phrase
    static func randomError() -> String {
        error.randomElement() ?? error[0]
    }

    /// Reset last-used tracking (useful for testing)
    static func reset() {
        lastGathering = nil
        lastThinking = nil
        lastReady = nil
    }
}
