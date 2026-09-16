import Testing
@testable import SuperPaste

struct PasteFailureTests {
    @Test func rejectedKeyOpensConfiguration() {
        let failure = PasteFailure.provider(.invalidAPIKey)
        #expect(failure.code == .providerConfiguration)
        #expect(failure.recovery == .openSettings)
    }

    @Test func timeoutOffersRetry() {
        #expect(PasteFailure.provider(.timeout).recovery == .retry)
    }

    @Test func quotaDoesNotOfferRetry() {
        #expect(PasteFailure.provider(.dailyLimitReached).recovery == nil)
    }

    @Test func destinationChangeOffersCopy() {
        #expect(PasteFailure.destinationChanged.recovery == .copyResponse)
    }
}
