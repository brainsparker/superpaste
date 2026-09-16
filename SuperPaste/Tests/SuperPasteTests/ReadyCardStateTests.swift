import Testing
@testable import SuperPaste

@MainActor
struct ReadyCardStateTests {
    @Test func firstSessionShowsPractice() {
        #expect(!ReadyCardState(hasTriedOnce: false).showReturningCard)
    }

    @Test func returningSessionSkipsPractice() {
        #expect(ReadyCardState(hasTriedOnce: true).showReturningCard)
    }

    @Test func generationDoesNotCompleteOnboarding() {
        let state = ReadyCardState(hasTriedOnce: false)
        state.continueToApps(progress: .generated)
        #expect(!state.showReturningCard)
    }

    @Test func manualInputDoesNotCompleteOnboarding() {
        let state = ReadyCardState(hasTriedOnce: false)
        state.continueToApps(progress: .idle)
        #expect(!state.showReturningCard)
    }

    @Test func insertedReplyWaitsForExplicitContinue() {
        let state = ReadyCardState(hasTriedOnce: false)
        #expect(!state.showReturningCard)
        state.continueToApps(progress: .inserted)
        #expect(state.showReturningCard)
    }
}
