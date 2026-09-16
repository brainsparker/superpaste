import Combine

enum PracticeProgress: String {
    case idle = "Click the reply field and press your shortcut."
    case hotkeyReceived = "Shortcut received."
    case captured = "Window captured. Writing a draft…"
    case generated = "Reply generated. Waiting for insertion…"
    case inserted = "Reply inserted. This is a draft. Nothing has been sent."
}

@MainActor
final class ReadyCardState: ObservableObject {
    @Published private(set) var showReturningCard: Bool

    init(hasTriedOnce: Bool) {
        showReturningCard = hasTriedOnce
    }

    func continueToApps(progress: PracticeProgress) {
        guard progress == .inserted else { return }
        showReturningCard = true
    }
}
