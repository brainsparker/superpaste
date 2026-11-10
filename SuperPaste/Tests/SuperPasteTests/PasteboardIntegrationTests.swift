import AppKit
import Testing
@testable import SuperPaste

/// Real NSPasteboard round-trip through ClipboardService (no mocks), plus the
/// transaction contract end-to-end. Each test has an isolated named pasteboard.
@Suite(.serialized)
@MainActor
struct PasteboardIntegrationTests {
    private let clipboard = ClipboardService(pasteboard: .withUniqueName())
    @Test func writeAndReadRoundTrip() {
        let unique = "superpaste-integration-\(UUID().uuidString)"
        clipboard.write(unique)
        #expect(clipboard.read() == unique)
    }

    @Test func nonemptyRestorationPreservesContents() {
        #expect(clipboard.write("original clipboard"))
        let original = clipboard.snapshotItems()
        #expect(clipboard.write("temporary response"))
        #expect(clipboard.restore(original))
        #expect(clipboard.read() == "original clipboard")
    }

    @Test func emptyRestoreClearsContents() {
        #expect(clipboard.restore([]))
        #expect(clipboard.read() == nil)
    }

    @Test func transactionRefusesStaleDestination() async {
        let service = clipboard
        let previous = service.snapshotItems()
        var pasteCalls = 0
        let outcome = await PasteTransaction.run(
            isCurrent: { true },
            destinationMatches: { false },
            clipboardMatches: { true },
            prepareClipboard: { service.write("superpaste must never leave this on the clipboard") },
            restoreClipboard: { service.restore(previous) },
            paste: { pasteCalls += 1; return true },
            wait: {}
        )
        #expect(outcome == .destinationChanged)
        #expect(service.read() != "superpaste must never leave this on the clipboard")
        #expect(pasteCalls == 0)
    }

    @Test func transactionRefusesUserClipboardChange() async {
        var pasteCalls = 0
        let outcome = await PasteTransaction.run(
            isCurrent: { true },
            destinationMatches: { true },
            clipboardMatches: { false },
            prepareClipboard: { clipboard.write("superseded-\(UUID().uuidString)") },
            restoreClipboard: {},
            paste: { pasteCalls += 1; return true },
            wait: {}
        )
        #expect(outcome == .clipboardChanged)
        #expect(pasteCalls == 0)
    }

    @Test func successfulRunPastesExactlyOnce() async {
        let service = clipboard
        let unique = "superpaste-pasted-\(UUID().uuidString)"
        var pasteCalls = 0
        let outcome = await PasteTransaction.run(
            isCurrent: { true },
            destinationMatches: { true },
            clipboardMatches: { true },
            prepareClipboard: { service.write(unique) },
            restoreClipboard: {},
            paste: { pasteCalls += 1; return true },
            wait: {}
        )
        #expect(outcome == .pasted)
        #expect(pasteCalls == 1)
        #expect(service.read() == unique)
    }
}
