import Foundation

/// A small reserve of personality for requests that take longer than normal.
enum HUDPhrases {
    static let slowThinking: [String] = [
        "Matching the vibe…",
        "Giving it a quick polish…",
        "Teaching the words some manners…"
    ]

    private static var lastSlowThinking: String?

    static func randomSlowThinking() -> String {
        let available = slowThinking.filter { $0 != lastSlowThinking }
        let phrase = available.randomElement() ?? slowThinking[0]
        lastSlowThinking = phrase
        return phrase
    }
}
