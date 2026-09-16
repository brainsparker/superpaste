import Testing
@testable import SuperPaste

struct ResponseSettingsTests {

    // MARK: - ResponseTone

    @Test func allTonesHaveUniqueRawValues() {
        let rawValues = ResponseTone.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test func allTonesHaveDisplayNames() {
        for tone in ResponseTone.allCases {
            #expect(!tone.displayName.isEmpty)
            #expect(!tone.description.isEmpty)
            #expect(!tone.promptFragment.isEmpty)
        }
    }

    @Test func matchContextPromptFragmentIsDefault() {
        // .matchContext should be the default (first case).
        #expect(ResponseTone.matchContext.promptFragment.contains("Match the tone"))
    }

    @Test func casualPromptFragmentContainsCasual() {
        #expect(ResponseTone.casual.promptFragment.contains("casual"))
    }

    @Test func professionalPromptFragmentContainsProfessional() {
        #expect(ResponseTone.professional.promptFragment.contains("professional"))
    }

    // MARK: - ResponseLength

    @Test func allLengthsHaveUniqueRawValues() {
        let rawValues = ResponseLength.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test func allLengthsHaveDisplayNames() {
        for length in ResponseLength.allCases {
            #expect(!length.displayName.isEmpty)
            #expect(!length.description.isEmpty)
            #expect(!length.promptFragment.isEmpty)
        }
    }

    @Test func balancedPromptFragmentIsNatural() {
        #expect(ResponseLength.balanced.promptFragment.contains("natural"))
    }

    @Test func concisePromptFragmentMentionsShort() {
        #expect(ResponseLength.concise.promptFragment.contains("concise"))
    }

    @Test func detailedPromptFragmentMentionsThorough() {
        #expect(ResponseLength.detailed.promptFragment.contains("thorough"))
    }
}