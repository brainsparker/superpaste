import Testing
@testable import SuperPaste

@MainActor
struct PasteTransactionTests {
    private final class Harness {
        var active = true
        var focused = true
        var clipboardUnchanged = true
        var preparations = 0
        var restores = 0
        var pastes = 0

        func run(wait: () async throws -> Void = {}) async -> PasteTransaction.Outcome {
            await PasteTransaction.run(
                isCurrent: { self.active },
                destinationMatches: { self.focused },
                clipboardMatches: { self.clipboardUnchanged },
                prepareClipboard: { self.preparations += 1 },
                restoreClipboard: { self.restores += 1 },
                paste: { self.pastes += 1; return true },
                wait: wait
            )
        }
    }

    @Test func unchangedDestinationPastesOnce() async {
        let harness = Harness()
        let outcome = await harness.run()
        #expect(outcome == .pasted)
        #expect(harness.pastes == 1)
    }

    @Test func unknownDestinationLeavesClipboardAlone() async {
        let harness = Harness()
        harness.focused = false
        let outcome = await harness.run()
        #expect(outcome == .destinationChanged)
        #expect(harness.preparations == 0)
        #expect(harness.pastes == 0)
    }

    @Test func focusChangeDuringWaitRestoresClipboard() async {
        let harness = Harness()
        let outcome = await harness.run { harness.focused = false }
        #expect(outcome == .destinationChanged)
        #expect(harness.restores == 1)
        #expect(harness.pastes == 0)
    }

    @Test func cancellationDuringWaitRestoresClipboard() async {
        let harness = Harness()
        let outcome = await harness.run { throw CancellationError() }
        #expect(outcome == .cancelled)
        #expect(harness.restores == 1)
        #expect(harness.pastes == 0)
    }

    @Test func cancelledGenerationCannotPaste() async {
        let harness = Harness()
        let outcome = await harness.run { harness.active = false }
        #expect(outcome == .cancelled)
        #expect(harness.pastes == 0)
    }

    @Test func userClipboardChangeIsNotOverwritten() async {
        let harness = Harness()
        let outcome = await harness.run { harness.clipboardUnchanged = false }
        #expect(outcome == .clipboardChanged)
        #expect(harness.restores == 0)
        #expect(harness.pastes == 0)
    }

    @Test func supersededRequestCannotBecomeCurrentAgain() {
        var token = PipelineToken()
        let old = token.advance()
        let current = token.advance()
        #expect(!token.accepts(old))
        #expect(token.accepts(current))
    }
}
