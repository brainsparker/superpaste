import Foundation

/// Phrase pools for each HUD stage.
/// Provides rotating, emoji-prefixed phrases for delight.
enum HUDPhrases {

    // MARK: - Phrase Pools

    static let gathering: [String] = [
        "📋 Gathering context...",
        "👀 Reading the room...",
        "🔍 Scanning the scene...",
        "📖 Taking it all in...",
        "🎯 Locking on...",
        "📡 Picking up signals...",
        "🧲 Pulling it together...",
        "👁️ Sizing things up...",
        "🌐 Getting the lay of the land...",
        "🎬 Setting the stage..."
    ]

    static let thinking: [String] = [
        "🧠 Thinking...",
        "✨ Brewing magic...",
        "⚡ Neurons firing...",
        "🔮 Consulting the oracle...",
        "💭 Pondering...",
        "🎨 Crafting words...",
        "⚙️ Crunching...",
        "🌀 Processing...",
        "💫 Conjuring...",
        "🧪 Mixing ingredients...",
        "🎹 Composing...",
        "🔥 Cooking...",
        "🚀 Revving up...",
        "🎯 Dialing it in...",
        "🌟 Working some magic..."
    ]

    static let ready: [String] = [
        "✨ Ready to Super Paste!",
        "🎉 Nailed it!",
        "💫 Your words await!",
        "🚀 Locked and loaded!",
        "✅ Good to go!",
        "🎯 Bullseye!",
        "⚡ Ready when you are!",
        "🌟 Fresh out the oven!",
        "💎 Polished and ready!",
        "🎁 Special delivery!"
    ]

    static let error: [String] = [
        "😅 Oops, hit a snag",
        "🔌 Connection hiccup",
        "🤔 Something went sideways",
        "🛠️ Technical difficulties",
        "📡 Lost the signal"
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
