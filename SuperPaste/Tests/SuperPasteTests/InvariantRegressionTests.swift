import Foundation
import CoreGraphics
import Testing
@testable import SuperPaste

@MainActor
struct InvariantRegressionTests {
    @Test func failedClipboardPreparationNeverPastes() async {
        var pastes = 0
        var restores = 0
        let result = await PasteTransaction.run(isCurrent: { true }, destinationMatches: { true },
            clipboardMatches: { true }, prepareClipboard: { false }, restoreClipboard: { restores += 1 },
            paste: { pastes += 1; return true }, wait: {})
        #expect(result == .clipboardUnavailable)
        #expect(pastes == 0)
        #expect(restores == 1)
    }

    @Test func clipboardOwnershipSurvivesRepeatButNotExternalCopy() {
        let ownership = ClipboardRestoration<String>()
        var restored = ""
        ownership.remember("campaign link", changeCount: 10)
        #expect(ownership.settle(changeCount: 10) { restored = $0; return true })
        #expect(restored == "campaign link")
        ownership.remember("old clipboard", changeCount: 12)
        #expect(ownership.settle(changeCount: 13) { _ in Issue.record("must preserve external copy"); return true })
    }

    @Test func failedRestorationRemainsRetryable() {
        let ownership = ClipboardRestoration<[String]>()
        ownership.remember([], changeCount: 4)
        #expect(!ownership.settle(changeCount: 4) { _ in false })
        var emptyWasRestored = false
        #expect(ownership.settle(changeCount: 4) { emptyWasRestored = $0.isEmpty; return true })
        #expect(emptyWasRestored)
    }

    @Test func captureWindowMatchingRejectsAmbiguityAndWrongWindows() {
        let frame = CGRect(x: 10, y: 20, width: 500, height: 400)
        func candidate(_ id: Int, pid: Int32 = 42, title: String = "Document") -> [String: Any] {
            [kCGWindowNumber as String: NSNumber(value: id), kCGWindowOwnerPID as String: pid,
             kCGWindowLayer as String: 0, kCGWindowName as String: title,
             kCGWindowBounds as String: frame.dictionaryRepresentation]
        }
        #expect(PasteDestination.matchingWindowID(frame: frame, title: "Document", pid: 42, windows: [candidate(1, pid: 99), candidate(2)]) == 2)
        #expect(PasteDestination.matchingWindowID(frame: frame, title: "Other", pid: 42, windows: [candidate(1)]) == nil)
        #expect(PasteDestination.matchingWindowID(frame: frame, title: "Document", pid: 42, windows: [candidate(1), candidate(2)]) == nil)
    }

    @Test func insertionContextIncludesValueAndSelection() {
        let original = InsertionContext(value: "hello", selectionLocation: 5, selectionLength: 0)
        #expect(original != InsertionContext(value: "new reply", selectionLocation: 5, selectionLength: 0))
        #expect(original != InsertionContext(value: "hello", selectionLocation: 0, selectionLength: 5))
    }

    @Test func permissionRevocationIsPublished() {
        var granted = true
        let manager = PermissionManager(screenProbe: { granted })
        #expect(manager.screenRecordingEnabled)
        granted = false
        #expect(!manager.checkPermission())
        #expect(!manager.screenRecordingEnabled)
    }

    @Test func remoteHostnameCannotMasqueradeAsLoopback() {
        #expect(!LocalEndpoint.isLoopback("https://127.attacker.example"))
        #expect(!LocalEndpoint.isLoopback("http://127.999.1.2"))
        #expect(!LocalEndpoint.isLoopback("http://0.0.0.0"))
        #expect(LocalEndpoint.isLoopback("http://127.0.0.2"))
    }

    @Test func invalidEndpointIsNotReadyAndCannotLeakDiagnostics() {
        for endpoint in ["ftp://example.com", "not a valid endpoint?api_key=secret", "https://user:password@example.com", "https://example.com:99999"] {
            let config = LLMProviderConfig(provider: .custom, model: "", customEndpoint: endpoint)
            #expect(config.resolvedEndpoint == nil)
            #expect(!config.isOwnProviderReady)
            #expect(LocalEndpoint.displayHost(endpoint) == "Invalid endpoint")
        }
    }

    @Test func credentialsHaveAnExplicitEndpointScope() {
        let first = UserCredentialStore.credentialService(for: .custom, endpoint: "https://a.example/v1")
        #expect(first != UserCredentialStore.credentialService(for: .custom, endpoint: "https://b.example/v1"))
        #expect(first != UserCredentialStore.credentialService(for: .custom, endpoint: "https://a.example/other/v1"))
        #expect(first == UserCredentialStore.credentialService(for: .custom, endpoint: "https://a.example:443/v1/"))
    }

    @Test func providerDefaultsDoNotCarryAnotherProvidersEndpointOrModel() {
        // Use an untouched provider-specific store; no live keys or connections are needed.
        let suite = UserDefaults.standard
        let name = "llmProviderConfig.ollama"
        let before = suite.object(forKey: name)
        suite.removeObject(forKey: name)
        defer { if let before { suite.set(before, forKey: name) } }
        let config = LLMService.config(for: .ollama)
        #expect(config.model.isEmpty)
        #expect(config.resolvedEndpoint == LLMProviderID.ollama.endpointURL)
    }

    @Test func completeAnthropicTextBlocksAreAssembled() throws {
        let data = Data(#"{"content":[{"type":"thinking"},{"type":"text","text":"Hello"},{"type":"text","text":"world"}],"stop_reason":"end_turn"}"#.utf8)
        #expect(try LLMService.shared.parseAnthropicResponse(data: data) == "Hello\nworld")
    }

    @Test func incompleteAndBlankResponsesAreRefused() {
        for body in [
            #"{"content":[{"type":"text","text":"   "}],"stop_reason":"end_turn"}"#,
            #"{"content":[{"type":"text","text":"partial"}],"stop_reason":"max_tokens"}"#
        ] {
            #expect(throws: (any Error).self) { try LLMService.shared.parseAnthropicResponse(data: Data(body.utf8)) }
        }
        for body in [
            #"{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}"#,
            #"{"choices":[{"message":{"content":"   "},"finish_reason":"stop"}]}"#,
            #"{"choices":[{"message":{"content":"unverified"}}]}"#
        ] {
            #expect(throws: (any Error).self) { try LLMService.shared.parseOpenAIResponse(data: Data(body.utf8)) }
        }
    }
}
