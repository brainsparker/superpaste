import Foundation
import Testing
@testable import SuperPaste

struct LLMProviderTests {

    @Test func allProvidersHaveUniqueRawValuesAndNames() {
        let raw = LLMProviderID.allCases.map(\.rawValue)
        #expect(Set(raw).count == raw.count)
        let names = LLMProviderID.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
        for provider in LLMProviderID.allCases {
            #expect(!provider.description.isEmpty)
        }
    }

    @Test func localProvidersNeedNoKey() {
        #expect(LLMProviderID.ollama.isLocal)
        #expect(LLMProviderID.lmstudio.isLocal)
        #expect(!LLMProviderID.ollama.requiresAPIKey)
        #expect(!LLMProviderID.lmstudio.requiresAPIKey)
        #expect(!LLMProviderID.custom.requiresAPIKey)
        #expect(LLMProviderID.anthropic.requiresAPIKey)
        #expect(LLMProviderID.openai.requiresAPIKey)
        #expect(LLMProviderID.openrouter.requiresAPIKey)
    }

    @Test func localProvidersAreBringYourOwnButNotCustom() {
        for provider in [LLMProviderID.ollama, .lmstudio] {
            #expect(provider.isBringYourOwnKey)
            #expect(provider.supportsCustomEndpoint)
            #expect(provider.supportsModelDiscovery)
            #expect(provider.supportsCustomModel)
            #expect(provider.defaultModel.isEmpty)
        }
        #expect(!LLMProviderID.anthropic.supportsCustomEndpoint)
        #expect(!LLMProviderID.superpaste.isBringYourOwnKey)
    }

    @Test func localDefaultEndpointsAreTheServersDefaultPorts() {
        #expect(LLMProviderID.ollama.endpointURL == "http://localhost:11434/v1/chat/completions")
        #expect(LLMProviderID.lmstudio.endpointURL == "http://localhost:1234/v1/chat/completions")
        for provider in LLMProviderID.allCases where !provider.endpointURL.isEmpty {
            #expect(URL(string: provider.endpointURL) != nil)
        }
    }

    @Test func installLinksExistForLocalProviders() {
        #expect(LLMProviderID.ollama.signupURL?.host == "ollama.com")
        #expect(LLMProviderID.lmstudio.signupURL?.host == "lmstudio.ai")
        #expect(LLMProviderID.ollama.signupLabel == "Install Ollama")
        #expect(LLMProviderID.anthropic.signupLabel.contains("API key"))
    }

    // MARK: - LLMProviderConfig.resolvedEndpoint

    @Test func localProviderFallsBackToDefaultEndpoint() {
        let config = LLMProviderConfig(provider: .ollama, model: "", customEndpoint: "")
        #expect(config.resolvedEndpoint == LLMProviderID.ollama.endpointURL)
        let spaced = LLMProviderConfig(provider: .lmstudio, model: "", customEndpoint: "   ")
        #expect(spaced.resolvedEndpoint == LLMProviderID.lmstudio.endpointURL)
    }

    @Test func localProviderHonorsEndpointOverride() {
        let config = LLMProviderConfig(provider: .ollama, model: "", customEndpoint: "192.168.1.20:11434")
        #expect(config.resolvedEndpoint == "http://192.168.1.20:11434/v1/chat/completions")
    }

    @Test func customProviderRequiresAnEndpoint() {
        let empty = LLMProviderConfig(provider: .custom, model: "", customEndpoint: "")
        #expect(empty.resolvedEndpoint == nil)
        #expect(!empty.isOwnProviderReady)
        let set = LLMProviderConfig(provider: .custom, model: "", customEndpoint: "https://gateway.example.com/v1")
        #expect(set.resolvedEndpoint == "https://gateway.example.com/v1/chat/completions")
    }

    @Test func hostedProviderIsNeverOwnProvider() {
        let config = LLMProviderConfig.default
        #expect(config.resolvedEndpoint == nil)
        #expect(!config.isOwnProviderReady)
        #expect(UserCredentialStore.activeProvider(for: config) == nil)
    }

    @Test func keylessLocalProviderCountsAsReady() {
        // This is what keeps a fully local user out of the trial-expired state:
        // no Keychain entry exists, and none is needed.
        let ollama = LLMProviderConfig(provider: .ollama, model: "", customEndpoint: "")
        #expect(ollama.isOwnProviderReady)
        #expect(UserCredentialStore.activeProvider(for: ollama) == .ollama)
        let lmstudio = LLMProviderConfig(provider: .lmstudio, model: "qwen3-vl", customEndpoint: "localhost:1234")
        #expect(lmstudio.isOwnProviderReady)
        #expect(UserCredentialStore.activeProvider(for: lmstudio) == .lmstudio)
    }

    @Test func keylessCustomEndpointCountsAsReady() {
        let config = LLMProviderConfig(provider: .custom, model: "", customEndpoint: "http://localhost:8080/v1")
        #expect(config.isOwnProviderReady)
    }

    @Test func configRoundTripsThroughJSON() throws {
        let original = LLMProviderConfig(provider: .lmstudio, model: "qwen3-vl", customEndpoint: "localhost:1234")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LLMProviderConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test func existingPersistedConfigStillDecodes() throws {
        // Shape written by 1.1.0 installs; adding providers must not break it.
        let legacy = #"{"provider":"custom","model":"gpt-4o","customEndpoint":"https://example.com/v1/chat/completions"}"#
        let decoded = try JSONDecoder().decode(LLMProviderConfig.self, from: Data(legacy.utf8))
        #expect(decoded.provider == .custom)
        #expect(decoded.resolvedEndpoint == "https://example.com/v1/chat/completions")
    }
}
