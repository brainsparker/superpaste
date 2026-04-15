import Foundation

/// Controls the tone of SuperPaste's responses
enum ResponseTone: String, CaseIterable, Identifiable {
    case matchContext = "matchContext"
    case casual = "casual"
    case professional = "professional"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .matchContext: return "Match context"
        case .casual: return "Casual"
        case .professional: return "Professional"
        }
    }

    var description: String {
        switch self {
        case .matchContext: return "Adapts to what's on screen"
        case .casual: return "Friendly and conversational"
        case .professional: return "Polished and formal"
        }
    }

    var promptFragment: String {
        switch self {
        case .matchContext: return "Match the tone of what's on screen (casual for chat, professional for email, technical for code)."
        case .casual: return "Always use a casual, friendly, conversational tone."
        case .professional: return "Always use a polished, professional, formal tone."
        }
    }
}

/// Controls the length of SuperPaste's responses
enum ResponseLength: String, CaseIterable, Identifiable {
    case concise = "concise"
    case balanced = "balanced"
    case detailed = "detailed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .concise: return "Concise"
        case .balanced: return "Balanced"
        case .detailed: return "Detailed"
        }
    }

    var description: String {
        switch self {
        case .concise: return "Short and to the point"
        case .balanced: return "Natural length for context"
        case .detailed: return "Thorough and complete"
        }
    }

    var promptFragment: String {
        switch self {
        case .concise: return "Keep responses very concise \u{2014} a few sentences at most. Brevity is key."
        case .balanced: return "Use a natural length that fits the context."
        case .detailed: return "Provide thorough, detailed responses. Don't cut corners."
        }
    }
}
