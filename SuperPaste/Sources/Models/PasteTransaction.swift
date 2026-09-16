import Foundation

@MainActor
enum PasteTransaction {
    enum Outcome: Equatable {
        case pasted, destinationChanged, clipboardChanged, pasteUnavailable, cancelled
    }

    static func run(
        isCurrent: () -> Bool,
        destinationMatches: () -> Bool,
        clipboardMatches: () -> Bool,
        prepareClipboard: () -> Void,
        restoreClipboard: () -> Void,
        paste: () -> Bool,
        wait: () async throws -> Void = { try await Task.sleep(for: .milliseconds(50)) }
    ) async -> Outcome {
        guard isCurrent() else { return .cancelled }
        guard destinationMatches() else { return .destinationChanged }
        guard clipboardMatches() else { return .clipboardChanged }
        prepareClipboard()
        do {
            try await wait()
            try Task.checkCancellation()
        } catch {
            if clipboardMatches() { restoreClipboard() }
            return .cancelled
        }
        guard isCurrent() else {
            if clipboardMatches() { restoreClipboard() }
            return .cancelled
        }
        guard clipboardMatches() else { return .clipboardChanged }
        guard destinationMatches() else {
            restoreClipboard()
            return .destinationChanged
        }
        guard paste() else {
            restoreClipboard()
            return .pasteUnavailable
        }
        return .pasted
    }
}

struct PipelineToken {
    private(set) var generation = 0

    mutating func advance() -> Int {
        generation += 1
        return generation
    }

    func accepts(_ candidate: Int) -> Bool {
        candidate == generation
    }
}
