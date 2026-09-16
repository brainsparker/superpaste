import Foundation
import Testing
@testable import SuperPaste

struct APIConfigTests {

    @Test func buildSystemPromptContainsModelName() {
        let prompt = APIConfig.buildSystemPrompt(personalContext: "")
        #expect(prompt.contains("SuperPaste"))
        #expect(prompt.contains("active-window context"))
    }

    @Test func buildSystemPromptRespectsTone() {
        let casualPrompt = APIConfig.buildSystemPrompt(personalContext: "", tone: .casual)
        let professionalPrompt = APIConfig.buildSystemPrompt(personalContext: "", tone: .professional)
        #expect(casualPrompt != professionalPrompt)
        #expect(casualPrompt.contains("casual"))
        #expect(professionalPrompt.contains("professional"))
    }

    @Test func buildSystemPromptRespectsLength() {
        let concisePrompt = APIConfig.buildSystemPrompt(personalContext: "", length: .concise)
        let detailedPrompt = APIConfig.buildSystemPrompt(personalContext: "", length: .detailed)
        #expect(concisePrompt != detailedPrompt)
        #expect(concisePrompt.contains("sentences"))
        #expect(detailedPrompt.contains("thorough"))
    }

    @Test func buildSystemPromptAppendsPersonalContext() {
        let prompt = APIConfig.buildSystemPrompt(personalContext: "I am a musician.")
        #expect(prompt.contains("musician"))
    }

    @Test func buildSystemPromptOmitsEmptyPersonalContext() {
        let withEmpty = APIConfig.buildSystemPrompt(personalContext: "")
        let withWhitespace = APIConfig.buildSystemPrompt(personalContext: "   ")
        #expect(withEmpty == withWhitespace)
    }

    @Test func buildSystemPromptContainsUnclearSentinel() {
        let prompt = APIConfig.buildSystemPrompt(personalContext: "")
        #expect(prompt.contains(APIConfig.unclearSentinel))
    }

    @Test func buildSystemPromptMentionsOutputFormat() {
        let prompt = APIConfig.buildSystemPrompt(personalContext: "")
        #expect(prompt.contains("Raw text"))
    }

    @Test func baseURLIsValidURL() {
        #expect(URL(string: APIConfig.baseURL) != nil)
    }

    @Test func anthropicDirectURLIsValid() {
        #expect(URL(string: APIConfig.anthropicDirectURL) != nil)
    }

    @Test func validateLicenseURLIsValid() {
        #expect(URL(string: APIConfig.validateLicenseURL) != nil)
    }
}